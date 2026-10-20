-- Fast `[[` / `[` link completion for obsidian.nvim (the 3.x pinned here).
--
-- Upstream's nvim-cmp source finds candidates with `rg --fixed-strings` over
-- every note BODY, then parses each matching note. In this 16k-note vault
-- `[[ta` matched 15.7k notes and took 11 s (`[[tap` ~1 s), and nvim-cmp asks
-- again on every keystroke, so suggestions crawled in (bug 2026-10-05).
-- Link targets are names, not body text. So while that source runs, its
-- search (`Client._search_iter_async`) is swapped for a lookup in a cached
-- name index: filename stems plus frontmatter aliases, built by one
-- `rg --files` and vault_alias_search's alias scan (~0.6 s, off the main
-- loop). Only the best LIMIT matches are parsed as notes. Newer obsidian.nvim
-- does the same with its metadata cache; this is the backport. Every other
-- search (follow link, rename, :ObsidianLink, ...) keeps upstream's.
local M = {}

-- Notes handed to the completion source per query. nvim-cmp asks again on
-- every keystroke, so a longer query narrows the set instead of paging it.
local LIMIT = 100
-- A query against an index older than this starts a background rebuild; the
-- query itself still answers from the current index. Parsing a rebuild holds
-- the main loop ~0.1 s, so not every few seconds; new notes don't wait for
-- this (see the BufWritePost below), only alias/title edits do.
local MAX_AGE_MS = 5 * 60 * 1000

---@type table<string, {entries: table[]|nil, paths: table<string, true>, built: integer, scanning: boolean, waiters: function[]}>
local indexes = {}

local function build(root)
	local idx = indexes[root]
	if idx.scanning then
		return
	end
	idx.scanning = true
	local files, aliases, titles
	local pending = 3
	local function finish()
		pending = pending - 1
		if pending > 0 then
			return
		end
		vim.schedule(function()
			idx.scanning = false
			if files then
				local entries, paths = {}, {}
				for rel in files:gmatch("[^\n]+") do
					local abs = root .. "/" .. rel
					local lnames = { (vim.fs.basename(rel):gsub("%.md$", "")):lower() }
					for _, a in ipairs(aliases and aliases[abs] or {}) do
						lnames[#lnames + 1] = a:lower()
					end
					vim.list_extend(lnames, titles and titles[rel] or {})
					entries[#entries + 1] = { path = abs, rel = rel, lrel = rel:lower(), lnames = lnames }
					paths[abs] = true
				end
				idx.entries, idx.paths, idx.built = entries, paths, vim.uv.now()
			end
			local waiters = idx.waiters
			idx.waiters = {}
			for _, w in ipairs(waiters) do
				w(idx)
			end
		end)
	end
	-- Same file set as upstream's search: markdown, .gitignore and hidden dirs skipped.
	vim.system({ "rg", "--no-config", "--type=md", "--files" }, { cwd = root, text = true }, function(res)
		if res.code == 0 or res.code == 1 then
			files = res.stdout or ""
		end
		finish()
	end)
	require("configs.vault_alias_search").scan_aliases(root, function(map)
		aliases = map
		finish()
	end)
	-- Frontmatter id/title and the first `# H1`, the other names a note goes by.
	-- -m3 is enough for id + title + H1; a later H1 is a section, not a name.
	vim.system({
		"rg", "--no-config", "--type=md", "-m3", "-o", "--null", "--no-heading", "--with-filename", "--color=never",
		"-e", [[^(?:id|title): *\S.*$]], "-e", [[^# +\S.*$]],
	}, { cwd = root, text = true }, function(res)
		if res.code == 0 or res.code == 1 then
			titles = {}
			local h1_seen = {}
			for rel, text in (res.stdout or ""):gmatch("([^%z\n]+)%z([^\n]*)") do
				local name = text:match("^%a+:%s*(.-)%s*$")
				if not name and not h1_seen[rel] then
					h1_seen[rel] = true
					name = text:match("^#%s+(.-)%s*$")
				end
				name = name and name:gsub("^[\"']", ""):gsub("[\"']$", "")
				if name and name ~= "" then
					titles[rel] = titles[rel] or {}
					table.insert(titles[rel], name:lower())
				end
			end
		end
		finish()
	end)
end

--- cb(idx) now if the index exists (rebuilding in the background when stale),
--- else as soon as the first build lands.
local function with_index(root, cb)
	local idx = indexes[root]
	if not idx then
		idx = { paths = {}, built = 0, scanning = false, waiters = {} }
		indexes[root] = idx
	end
	if idx.entries then
		if vim.uv.now() - idx.built > MAX_AGE_MS then
			build(root)
		end
		cb(idx)
	else
		table.insert(idx.waiters, cb)
		build(root)
	end
end

--- 0 exact, 1 prefix, 2 starts a word, 3 anywhere; nil if `q` is not in `name`.
local function score(name, q)
	local s, e = name:find(q, 1, true)
	if not s then
		return nil
	end
	if s == 1 then
		return e == #name and 0 or 1
	end
	return name:find("[%s_./-]" .. vim.pesc(q)) and 2 or 3
end

--- Paths of the best LIMIT notes whose stem or an alias contains `term`.
local function rank(idx, term, skip_dir)
	local q = vim.trim(term):lower()
	local qs = { q }
	local slug = q:gsub("%s+", "-") -- "trigger action" also finds trigger-action-planning.md
	if slug ~= q then
		qs[2] = slug
	end
	local path_query = q:find("/", 1, true) ~= nil
	local hits = {}
	for _, e in ipairs(idx.entries) do
		if not (skip_dir and ("/" .. e.lrel):find(skip_dir, 1, true)) then
			local best, len
			for _, name in ipairs(e.lnames) do
				for _, qq in ipairs(qs) do
					local s = score(name, qq)
					if s and (not best or s < best or (s == best and #name < len)) then
						best, len = s, #name
					end
				end
			end
			if not best and path_query then
				best, len = score(e.lrel, q), #e.lrel
			end
			if best then
				hits[#hits + 1] = { path = e.path, rel = e.rel, s = best, len = len }
			end
		end
	end
	table.sort(hits, function(a, b)
		if a.s ~= b.s then
			return a.s < b.s
		end
		if a.len ~= b.len then
			return a.len < b.len
		end
		return a.rel < b.rel
	end)
	local out = {}
	for i = 1, math.min(LIMIT, #hits) do
		out[i] = hits[i].path
	end
	return out
end

--- Stand-in for Client._search_iter_async: an iterator over matching note
--- paths, consumed inside find_notes_async's coroutine.
local function search_iter(client, term)
	local Path = require("obsidian.path")
	local tx, rx = require("plenary.async.control").channel.mpsc()
	local folder = client.opts.templates and client.opts.templates.folder
	-- Upstream leaves the templates folder out of completion (-g!templates).
	local skip = folder and ("/" .. tostring(folder):lower() .. "/") or nil
	with_index(tostring(client.dir), function(idx)
		if idx.entries then
			for _, p in ipairs(rank(idx, term, skip)) do
				tx.send(Path.new(p))
			end
		end
		tx.send(nil)
	end)
	local done = false
	return function()
		-- Executor.map calls once more after the first nil; a second recv()
		-- would wait forever, so stay at nil.
		if done then
			return nil
		end
		local p = rx.recv()
		done = p == nil
		return p
	end
end

function M.setup()
	local source = require("cmp_obsidian")
	local complete = source.complete
	source.complete = function(self, request, callback)
		local client = require("obsidian")._client
		if not client then
			return complete(self, request, callback)
		end
		-- An instance field shadows Client._search_iter_async for exactly this
		-- call: complete() reaches find_notes_async -> _search_iter_async
		-- synchronously, before anything yields.
		client._search_iter_async = search_iter
		local ok, err = pcall(complete, self, request, callback)
		client._search_iter_async = nil
		if not ok then
			error(err, 0)
		end
	end

	local client = require("obsidian")._client
	if not client then
		return
	end
	local root = tostring(client.dir)
	-- Build now so the session's first `[[` is already fast.
	with_index(root, function() end)
	-- A new note shows up from the next keystroke after its first write.
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = vim.api.nvim_create_augroup("ObsidianLinkIndex", { clear = true }),
		pattern = "*.md",
		callback = function(ev)
			local idx = indexes[root]
			local path = vim.fs.normalize(vim.fn.fnamemodify(ev.match, ":p"))
			if idx and idx.entries and vim.startswith(path, root .. "/") and not idx.paths[path] then
				build(root)
			end
		end,
	})
end

return M
