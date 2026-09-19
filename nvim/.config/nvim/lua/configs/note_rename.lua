-- Name notes after their title, and keep links pointing at them.
--
-- New notes: obsidian.nvim's note_id_func (plugins/init.lua) calls M.slug(title),
-- so `:ObsidianNew What I will do` creates what-i-will-do.md directly.
--
-- Notes created WITHOUT a title get obsidian's timestamp id (1789411698-ZTCV.md).
-- On write, such a note is renamed to the dash-case of its first `# H1`:
--
--   * the file is moved on disk and the buffer is re-pointed at the new path,
--     so further edits go to the new file (not a resurrected old one);
--   * the frontmatter `id:` is updated to match;
--   * links to it are rewritten across the vault (see M.update_links).
--
-- Only timestamp-named notes are renamed automatically, so a note is renamed
-- once -- editing its H1 later does not keep moving the file. Notes with
-- `public: true` are skipped, since their filename may be a published URL.
-- :NoteRenameFromTitle does the same for the current note unconditionally.
--
-- Renaming/moving a note (or a folder of notes) in oil.nvim rewrites links too.
--
-- Link rewriting, and the edge cases it handles:
--   * references in LOADED buffers are rewritten in the buffer, unsaved text
--     included (a link typed seconds ago is not on disk yet); buffers with no
--     other unsaved changes are written back, modified ones are left to save;
--   * files in .gitignored folders (journal/, personal/, ...) are searched too;
--     hidden dirs (.git, .claude worktrees, .trash) and node_modules are not;
--   * [[id]], [[id|a]], [[id#h]], [[id.md]], ![[id]], [[dir/id]], table `\|`,
--     and markdown ](id.md), ](./id.md), ](../dir/id.md#h), ](dir/id), ](<a b.md>);
--   * links in fenced code blocks are left alone;
--   * a bare [[name]] is only rewritten when no other note has that name
--     (another index.md elsewhere means [[index]] may not be this note); such
--     links are counted and reported instead of guessed at;
--   * title collisions: the new id gets -2, -3, ... until no note ANYWHERE in the
--     vault has that name, so [[new-id]] can never resolve to a different note;
--     for oil renames onto a name used elsewhere, links get the vault path.
local M = {}

local ZETTEL_ID = "^%d+%-%u%u%u%u$"

--- Dash-case a title into a filename-safe id. "What's next?" -> "whats-next".
function M.slug(title)
	local s = title:lower():gsub("’", ""):gsub("'", ""):gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
	return s
end

local function unquote(s)
	return (vim.trim(s):gsub("^[\"']", ""):gsub("[\"']$", ""))
end

--- { id_lnum, id, public, title } for a note's lines (frontmatter + first H1).
local function inspect_lines(lines)
	local info, body_start = {}, 1
	if lines[1] == "---" then
		for i = 2, #lines do
			local line = lines[i]
			if line == "---" or line == "..." then
				body_start = i + 1
				break
			end
			local id = line:match("^id:%s*(.-)%s*$")
			if id then
				info.id_lnum, info.id = i, unquote(id)
			end
			local public = line:match("^public:%s*(.-)%s*$")
			if public then
				info.public = unquote(public) == "true"
			end
		end
	end
	local in_fence = false
	for i = body_start, #lines do
		if lines[i]:match("^%s*```") then
			in_fence = not in_fence
		elseif not in_fence then
			local h1 = lines[i]:match("^#%s+(.-)%s*$")
			if h1 and h1 ~= "" then
				info.title = h1
				break
			end
		end
	end
	return info
end

local function inspect(buf)
	return inspect_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
end

local function exists(path)
	return vim.uv.fs_stat(path) ~= nil
end

local function realpath(p)
	return vim.uv.fs_realpath(p) or p
end

--- Collapse `.`/`..`/`//` in an absolute path (the target may not exist).
local function clean(p)
	local out = {}
	for seg in p:gmatch("[^/]+") do
		if seg == ".." then
			table.remove(out)
		elseif seg ~= "." then
			out[#out + 1] = seg
		end
	end
	return "/" .. table.concat(out, "/")
end

--- Relative path from directory `from` to file `to` (both absolute, clean).
local function relpath(from, to)
	local a, b = vim.split(from, "/", { trimempty = true }), vim.split(to, "/", { trimempty = true })
	local i = 1
	while i <= #a and i < #b and a[i] == b[i] do
		i = i + 1
	end
	local parts = {}
	for _ = i, #a do
		parts[#parts + 1] = ".."
	end
	for j = i, #b do
		parts[#parts + 1] = b[j]
	end
	return table.concat(parts, "/")
end

local function stem_of(p)
	return vim.fn.fnamemodify(p, ":t:r")
end

-- --no-ignore: gitignored note folders hold links too. Hidden dirs stay skipped
-- (.claude/worktrees alone is 56k copies of the vault's notes).
local RG_SCOPE = { "--no-ignore", "--glob", "*.md", "--glob", "!node_modules", "--color=never" }

--- The vault's .md files: lowercase stem -> count.
local function stem_counts(root)
	local res = vim.system(vim.list_extend({ "rg", "--files" }, vim.deepcopy(RG_SCOPE)), { cwd = root, text = true }):wait()
	local counts = {}
	for rel in (res.stdout or ""):gmatch("[^\n]+") do
		local s = stem_of(rel):lower()
		counts[s] = (counts[s] or 0) + 1
	end
	return counts
end

--- Vault root (dir holding .obsidian) for a path, or nil.
local function vault_root(path)
	local vault = vim.fs.find(".obsidian", { path = vim.fs.dirname(path), upward = true, type = "directory", limit = 1 })[1]
	return vault and realpath(vim.fs.dirname(vault)) or nil
end

--- Rewrite every link to notes that were just moved (they are already at `new`).
--- `moves` = list of { old = abs path, new = abs path, old_id = frontmatter id|nil }.
--- Returns { refs, files, dirty = {buffers updated but left unsaved}, ambiguous }.
function M.update_links(root, moves)
	root = realpath(root)
	local counts = stem_counts(root)
	local ms, needles = {}, {}
	for _, mv in ipairs(moves) do
		local m = {
			old = clean(mv.old),
			new = clean(realpath(vim.fs.dirname(mv.new)) .. "/" .. vim.fs.basename(mv.new)),
		}
		m.old_rel = m.old:sub(#root + 2):gsub("%.md$", "")
		m.new_rel = m.new:sub(#root + 2):gsub("%.md$", "")
		m.old_stem, m.new_stem = stem_of(m.old), stem_of(m.new)
		-- names a bare link could use for this note: filename and frontmatter id
		m.old_names = { [m.old_stem:lower()] = true }
		if mv.old_id and mv.old_id ~= "" then
			m.old_names[mv.old_id:lower()] = true
		end
		-- a bare old name is only this note's if no OTHER note still has it
		m.old_unique = {}
		for name in pairs(m.old_names) do
			local others = (counts[name] or 0) - (name == m.new_stem:lower() and 1 or 0)
			m.old_unique[name] = others <= 0
			needles[#needles + 1] = name
		end
		m.new_unique = (counts[m.new_stem:lower()] or 0) <= 1
		ms[#ms + 1] = m
	end

	local ambiguous = 0

	--- New target for a wiki link target, or nil if it is not a moved note.
	local function wiki_target(t, file_dir)
		local has_md = t:lower():match("%.md$") ~= nil
		local base = has_md and t:sub(1, -4) or t
		local lower = base:lower():gsub("^/", "")
		local ext = has_md and ".md" or ""
		for _, m in ipairs(ms) do
			if lower:find("/", 1, true) then
				if lower == m.old_rel:lower() or clean(file_dir .. "/" .. base):lower() == m.old:gsub("%.md$", ""):lower() then
					return m.new_rel .. ext
				end
			elseif m.old_names[lower] then
				if not m.old_unique[lower] then
					ambiguous = ambiguous + 1
					return nil
				end
				if lower == m.new_stem:lower() then
					return nil -- moved to another folder, same name: still resolves
				end
				return (m.new_unique and m.new_stem or m.new_rel) .. ext
			end
		end
	end

	--- New target for a markdown link target (anchor already split off), or nil.
	local function md_target(t, file_dir)
		if t:match("^%a[%w+.-]*:") then
			return nil -- URL
		end
		local decoded = t:gsub("%%(%x%x)", function(h)
			return string.char(tonumber(h, 16))
		end)
		local has_md = decoded:lower():match("%.md$") ~= nil
		local with_md = has_md and decoded or (decoded .. ".md")
		for _, m in ipairs(ms) do
			local old_l = m.old:lower()
			local new
			if decoded:sub(1, 1) ~= "/" and clean(file_dir .. "/" .. with_md):lower() == old_l then
				new = relpath(file_dir, m.new)
				if decoded:match("^%./") and not new:match("^%.%./") then
					new = "./" .. new
				end
			elseif clean(root .. "/" .. with_md):lower() == old_l then
				new = (decoded:sub(1, 1) == "/" and "/" or "") .. m.new:sub(#root + 2)
			elseif not decoded:find("/", 1, true) and not has_md and m.old_names[decoded:lower()] then
				-- `](old-id)` from another folder: obsidian resolves it by name
				if not m.old_unique[decoded:lower()] then
					ambiguous = ambiguous + 1
					return nil
				end
				new = m.new_unique and m.new_stem or m.new_rel
			end
			if new then
				if not has_md then
					new = new:gsub("%.md$", "")
				end
				if t:find("%20", 1, true) then
					new = new:gsub(" ", "%%20")
				end
				return new
			end
		end
	end

	--- Rewrite one note's lines in place; returns the number of links changed.
	local function rewrite(lines, abs)
		local file_dir = vim.fs.dirname(abs)
		local n, in_fence = 0, false
		local function sub(fn)
			return function(open, t)
				local new = fn(t, file_dir)
				if new and new ~= t then
					n = n + 1
					return open .. new
				end
			end
		end
		for i, line in ipairs(lines) do
			if line:match("^%s*```") or line:match("^%s*~~~") then
				in_fence = not in_fence
			elseif not in_fence and (line:find("[[", 1, true) or line:find("](", 1, true)) then
				-- [[target]] [[target|..]] [[target\|..]] [[target#..]] ![[target]]
				line = line:gsub("(%[%[)([^%]|#\\]+)", sub(wiki_target))
				-- ](<target with spaces>) and ](target#anchor "title")
				line = line:gsub("(%]%(<)([^>#]+)", sub(md_target))
				line = line:gsub("(%]%()([^%s%)#<>]+)", sub(md_target))
				lines[i] = line
			end
		end
		return n
	end

	-- Candidates: every loaded note buffer in the vault (its unsaved text counts)
	-- plus every file on disk that mentions an old name.
	local loaded, candidates = {}, {}
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		local name = vim.api.nvim_buf_get_name(b)
		if vim.api.nvim_buf_is_loaded(b) and name:match("%.md$") and vim.bo[b].buftype == "" then
			local abs = realpath(name)
			if abs:sub(1, #root + 1) == root .. "/" then
				loaded[abs], candidates[abs] = b, true
			end
		end
	end
	local args = vim.list_extend({ "rg", "-l", "-F", "-i" }, vim.deepcopy(RG_SCOPE))
	for _, nd in ipairs(needles) do
		vim.list_extend(args, { "-e", nd })
	end
	for _, m in ipairs(ms) do
		vim.list_extend(args, { "-e", vim.fs.basename(m.old) })
	end
	-- exit 2 = some file was unreadable (e.g. a sync temp file vanished mid-scan);
	-- the matches rg did print are still valid, so use stdout either way
	local res = vim.system(args, { cwd = root, text = true }):wait()
	for rel in (res.stdout or ""):gmatch("[^\n]+") do
		candidates[realpath(root .. "/" .. rel)] = true
	end

	local total, files, dirty, locked = 0, 0, {}, {}
	for abs in pairs(candidates) do
		local b = loaded[abs]
		local lines = b and vim.api.nvim_buf_get_lines(b, 0, -1, false) or vim.fn.readfile(abs)
		local before = vim.deepcopy(lines)
		local n = rewrite(lines, abs)
		if n > 0 then
			local wrote = true
			if b and (not vim.bo[b].modifiable or vim.bo[b].readonly) then
				-- A loaded-but-locked buffer can be neither edited (E21: Cannot
				-- make changes, 'modifiable' is off -- which used to abort the
				-- whole cascade, leaving SOME links rewritten and the rest not)
				-- nor written behind its back on disk, since that buffer would
				-- then be stale and saving it would undo the rewrite. Report it
				-- and leave both alone.
				locked[#locked + 1] = vim.fs.basename(abs)
				wrote = false
			elseif b then
				local was_modified = vim.bo[b].modified
				for i, line in ipairs(lines) do
					if line ~= before[i] then -- line by line: keeps marks, folds, cursor
						vim.api.nvim_buf_set_lines(b, i - 1, i, false, { line })
					end
				end
				if was_modified then
					dirty[#dirty + 1] = vim.fs.basename(abs)
				else
					-- noautocmd: no formatter run, no rename cascade from this write
					vim.api.nvim_buf_call(b, function()
						vim.cmd("noautocmd silent keepalt write")
					end)
				end
			else
				vim.fn.writefile(lines, abs)
			end
			if wrote then
				total, files = total + n, files + 1
			end
		end
	end
	return { refs = total, files = files, dirty = dirty, locked = locked, ambiguous = ambiguous }
end

local function report(prefix, r)
	local msg, level = prefix, vim.log.levels.INFO
	if r.refs > 0 then
		msg = msg .. (" (%d link%s in %d file%s)"):format(r.refs, r.refs == 1 and "" or "s", r.files, r.files == 1 and "" or "s")
	end
	if #r.dirty > 0 then
		msg = msg .. "\nupdated in unsaved buffers: " .. table.concat(r.dirty, ", ")
	end
	if r.locked and #r.locked > 0 then
		msg = msg .. "\nNOT updated (read-only buffer): " .. table.concat(r.locked, ", ")
		level = vim.log.levels.WARN
	end
	if r.ambiguous > 0 then
		msg = msg .. ("\n%d bare link%s left alone: another note has that name"):format(r.ambiguous, r.ambiguous == 1 and "" or "s")
		level = vim.log.levels.WARN
	end
	vim.notify(msg, level)
end

--- Rename `buf`'s note after its H1. `force` skips the timestamp-id/public guards.
function M.rename(buf, force)
	local path = vim.api.nvim_buf_get_name(buf)
	if path == "" or not path:match("%.md$") then
		return
	end
	local root = vault_root(path)
	if not root then
		return
	end
	local stem = stem_of(path)
	local info = inspect(buf)

	local function skip(msg)
		if force then
			vim.notify("NoteRename: " .. msg, vim.log.levels.WARN)
		end
	end
	if not force and (not stem:match(ZETTEL_ID) or info.public) then
		return
	end
	if not info.title then
		return skip("no `# title` heading to name the note after")
	end
	local slug = M.slug(info.title)
	if slug == "" then
		return skip("title has no filename-safe characters")
	end
	if slug == stem then
		return skip("already named " .. slug .. ".md")
	end

	-- Conflicting titles: take an id no other note in the vault has, so a bare
	-- [[new-id]] can't resolve to a same-named note in another folder.
	local counts = stem_counts(root)
	local dir = vim.fs.dirname(path)
	local new_id, target = slug, dir .. "/" .. slug .. ".md"
	local n = 2
	local function taken(id, t)
		if t:lower() == path:lower() then
			return false -- case-only rename: same file on macOS, not a collision
		end
		return exists(t) or (counts[id:lower()] or 0) > 0
	end
	while taken(new_id, target) do
		new_id = slug .. "-" .. n
		target = dir .. "/" .. new_id .. ".md"
		n = n + 1
	end

	local ok, err = vim.uv.fs_rename(path, target)
	if not ok then
		return vim.notify("NoteRename: could not rename: " .. tostring(err), vim.log.levels.ERROR)
	end

	if info.id_lnum and info.id == stem then
		vim.api.nvim_buf_set_lines(buf, info.id_lnum - 1, info.id_lnum, false, { "id: " .. new_id })
	end

	-- Re-point the buffer. :file semantics leave the old name behind as an
	-- unlisted alternate buffer and mark this one "not edited"; wipe the former
	-- and `write!` to clear the latter (noautocmd: the write that got us here
	-- already ran formatting and the frontmatter update).
	vim.api.nvim_buf_set_name(buf, target)
	local stale = vim.fn.bufnr(path)
	if stale ~= -1 and stale ~= buf then
		pcall(vim.api.nvim_buf_delete, stale, { force = true })
	end
	vim.api.nvim_buf_call(buf, function()
		vim.cmd("noautocmd silent keepalt write!")
	end)

	local r = M.update_links(root, { { old = realpath(dir) .. "/" .. stem .. ".md", new = target, old_id = info.id } })
	report(("Renamed %s.md → %s.md"):format(stem, new_id), r)
end

--- oil.nvim renamed/moved notes: keep their ids and the links to them in step.
local function on_oil_actions(actions)
	local by_root = {}
	for _, a in ipairs(actions) do
		if a.type == "move" and a.src_url and a.dest_url then
			local src, dest = a.src_url:gsub("^oil://", ""), a.dest_url:gsub("^oil://", "")
			src, dest = src:gsub("/$", ""), dest:gsub("/$", "")
			local root = vault_root(dest)
			if root and vault_root(src) == root then
				local notes = {}
				if a.entry_type == "directory" then
					for name, t in vim.fs.dir(dest, { depth = 50 }) do
						if t == "file" and name:match("%.md$") then
							notes[#notes + 1] = { src .. "/" .. name, dest .. "/" .. name }
						end
					end
				elseif src:match("%.md$") and dest:match("%.md$") then
					notes[1] = { src, dest }
				end
				for _, p in ipairs(notes) do
					local old, new = p[1], p[2]
					local b = vim.fn.bufnr(new)
					local live = b ~= -1 and vim.api.nvim_buf_is_loaded(b)
					local lines = live and vim.api.nvim_buf_get_lines(b, 0, -1, false) or vim.fn.readfile(new)
					local info = inspect_lines(lines)
					-- the id tracked the filename: keep it tracking
					if info.id_lnum and info.id == stem_of(old) and stem_of(old) ~= stem_of(new) then
						if live then
							vim.api.nvim_buf_set_lines(b, info.id_lnum - 1, info.id_lnum, false, { "id: " .. stem_of(new) })
						else
							lines[info.id_lnum] = "id: " .. stem_of(new)
							vim.fn.writefile(lines, new)
						end
					end
					by_root[root] = by_root[root] or {}
					table.insert(by_root[root], { old = old, new = new, old_id = info.id })
				end
			end
		end
	end
	for root, moves in pairs(by_root) do
		local r = M.update_links(root, moves)
		if r.refs > 0 or r.ambiguous > 0 then
			report(("Moved %d note%s"):format(#moves, #moves == 1 and "" or "s"), r)
		end
	end
end

local group = vim.api.nvim_create_augroup("NoteRenameFromTitle", { clear = true })

vim.api.nvim_create_autocmd("BufWritePost", {
	group = group,
	pattern = "*.md",
	callback = function(args)
		-- Ignore `:w other.md` (a copy), which also fires BufWritePost.
		if vim.fs.normalize(vim.fn.fnamemodify(args.file, ":p")) ~= vim.fs.normalize(vim.api.nvim_buf_get_name(args.buf)) then
			return
		end
		local ok, err = pcall(M.rename, args.buf, false)
		if not ok then
			vim.notify("NoteRename: " .. tostring(err), vim.log.levels.ERROR)
		end
	end,
})

vim.api.nvim_create_autocmd("User", {
	group = group,
	pattern = "OilActionsPost",
	callback = function(args)
		if args.data and not args.data.err and args.data.actions then
			local ok, err = pcall(on_oil_actions, args.data.actions)
			if not ok then
				vim.notify("NoteRename (oil): " .. tostring(err), vim.log.levels.ERROR)
			end
		end
	end,
})

vim.api.nvim_create_user_command("NoteRenameFromTitle", function()
	M.rename(vim.api.nvim_get_current_buf(), true)
end, { desc = "Rename the current note to the dash-case of its # title" })

return M
