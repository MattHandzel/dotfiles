-- Alias-aware smart search for Obsidian vaults.
--
-- Inside a vault (any cwd with a `.obsidian/` directory at or above it),
-- <leader><space> still runs Snacks.picker.smart(), but every note is matched
-- against several strings instead of one:
--
--   capture/raw_capture/1789411698-ZTCV.md                 (the real path)
--   capture/raw_capture/What I will be doing for the next week   (one per alias,
--   capture/raw_capture/what-i-will-be-doing-for-the-next-week    filename swapped)
--
-- The item's score is the best score across those strings, so a note shows up
-- once, ranked by whichever string matched best. When an alias wins, the alias
-- is shown dimmed after the path (the path itself is not highlighted, since the
-- match positions belong to the alias string, not the path).
--
-- Aliases come from one `rg` pass over the vault's frontmatter (~0.4s for 14k
-- notes), cached per vault and refreshed in the background on every open.
local M = {}

---@type table<string, {aliases: table<string, string[]>, scanning: boolean}>
local caches = {}

local function unquote(s)
	s = vim.trim(s)
	return (s:gsub("^[\"']", ""):gsub("[\"']$", ""))
end

--- Nearest ancestor of `dir` (inclusive) containing `.obsidian/`, or nil.
local function vault_root(dir)
	local found = vim.fs.find(".obsidian", { path = dir, upward = true, type = "directory", limit = 1 })[1]
	return found and vim.fs.dirname(found) or nil
end

--- Parse `rg --null` output (one `path\0line` per frontmatter line) into
--- { [absolute path] = { alias, ... } }.
local function parse(root, stdout)
	local out = {}
	local cur_path, in_list
	for line in stdout:gmatch("[^\n]+") do
		local rel, text = line:match("^([^%z]+)%z(.*)$")
		if rel then
			if rel ~= cur_path then
				cur_path, in_list = rel, false
			end
			local abs = root .. "/" .. rel
			local value = text:match("^aliases:%s*(.*)$")
			if value then
				in_list = false
				local inline = value:match("^%[(.*)%]%s*$")
				if inline then
					for part in inline:gmatch("[^,]+") do
						local a = unquote(part)
						if a ~= "" then
							out[abs] = out[abs] or {}
							table.insert(out[abs], a)
						end
					end
				elseif value ~= "" then
					out[abs] = { unquote(value) }
				else
					in_list = true
				end
			elseif in_list then
				local a = text:match("^%s+%-%s*(.-)%s*$")
				if a and a ~= "" then
					a = unquote(a)
					if a ~= "" then
						out[abs] = out[abs] or {}
						table.insert(out[abs], a)
					end
				end
			end
		end
	end
	return out
end

local RG_ARGS = {
	"rg",
	"--glob",
	"*.md",
	"-U",
	"-o",
	"--null",
	"--no-heading",
	"--with-filename",
	"--color=never",
	-- Frontmatter from line 1 up to and including the aliases block. Pre-alias
	-- lines may not start with "-", so the match cannot run past the closing ---.
	[[\A---\n(?:[^-\n].*\n|\n)*?aliases:.*\n(?:[ \t]+-.*\n)*]],
}

local function scan(root, cb)
	local cache = caches[root]
	if cache.scanning then
		return
	end
	cache.scanning = true
	vim.system(RG_ARGS, { cwd = root, text = true }, function(res)
		-- rg exits 1 when nothing matched; anything else non-zero is a real error.
		if res.code == 0 or res.code == 1 then
			cache.aliases = parse(root, res.stdout or "")
		end
		cache.scanning = false
		if cb then
			vim.schedule(cb)
		end
	end)
end

--- Ensure the matcher considers `item.alias_texts`. Patched once, and inert for
--- any item without that field, so other pickers are unaffected.
local function patch_matcher()
	local Matcher = require("snacks.picker.core.matcher")
	if Matcher._vault_alias_patched then
		return
	end
	Matcher._vault_alias_patched = true

	local match, positions = Matcher.match, Matcher.positions

	function Matcher:match(item)
		local texts = item.alias_texts
		if not texts or self:empty() then
			return match(self, item)
		end
		local best, best_text = match(self, item), nil
		for _, t in ipairs(texts) do
			local s = match(self, setmetatable({ text = t }, { __index = item }))
			if s > best then
				best, best_text = s, t
			end
		end
		item.alias_hit = best_text
		item.comment = best_text and ("  " .. vim.fn.fnamemodify(best_text, ":t")) or nil
		return best
	end

	function Matcher:positions(item)
		if item.alias_hit then
			return {}
		end
		return positions(self, item)
	end
end

--- Transform that attaches alias search strings to each file item.
--- Paths are built from the item's real path relative to `cwd`, not from
--- item.text: buffer items' text is "<bufnr> <path> <filetype>", and recent
--- files use absolute paths, so item.text is not a consistent path.
local function attach_aliases(root, cwd)
	return function(item)
		local path = Snacks.picker.util.path(item)
		local aliases = path and caches[root].aliases[path]
		if not aliases then
			return
		end
		local dir = vim.fs.dirname(vim.fs.relpath(cwd, path) or path)
		local prefix = (dir == "." or dir == "") and "" or (dir .. "/")
		local texts = {}
		for _, a in ipairs(aliases) do
			texts[#texts + 1] = prefix .. a
		end
		item.alias_texts = texts
	end
end

function M.smart(opts)
	opts = opts or {}
	local cwd = vim.fs.normalize(opts.cwd or vim.uv.cwd())
	local root = vault_root(cwd)
	if not root then
		return Snacks.picker.smart(opts)
	end

	patch_matcher()
	if not caches[root] then
		caches[root] = { aliases = {}, scanning = false }
		-- First open in this session: wait for the scan (~0.5s) so aliases are
		-- searchable immediately rather than only from the second open on.
		scan(root)
		vim.wait(3000, function()
			return not caches[root].scanning
		end, 20)
	else
		scan(root) -- refresh in the background for the next open
	end

	local attach = attach_aliases(root, cwd)
	return Snacks.picker.smart(vim.tbl_extend("force", opts, {
		-- Keep smart's own `unique_file` de-dup, then attach aliases.
		transform = function(item, ctx)
			if require("snacks.picker.transform").unique_file(item, ctx) == false then
				return false
			end
			attach(item)
		end,
	}))
end

return M
