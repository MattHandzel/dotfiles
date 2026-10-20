-- Name notes after their title.
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
--   * [[old-id]], [[old-id|..]], [[old-id#..]], ](old-id) and the vault-relative
--     path forms of those are rewritten across the vault (loaded buffers are
--     edited in place, not behind their back on disk).
--
-- Only timestamp-named notes are renamed automatically, so a note is renamed
-- once -- editing its H1 later does not keep moving the file. Notes with
-- `public: true` are skipped, since their filename may be a published URL.
-- :NoteRenameFromTitle does the same for the current note unconditionally.
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

--- { id_lnum, id, public, title } for a buffer's frontmatter + first H1.
local function inspect(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
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

local function exists(path)
	return vim.uv.fs_stat(path) ~= nil
end

--- Plain (non-pattern) replace-all.
local function replace_plain(s, from, to)
	local count
	s, count = s:gsub(vim.pesc(from), (to:gsub("%%", "%%%%")))
	return s, count
end

--- Rewrite links to the old id/path across the vault. Returns replacements, files.
local function update_backlinks(root, buf, old_id, new_id, old_rel, new_rel)
	local function forms(ref)
		return { "[[" .. ref .. "]]", "[[" .. ref .. "|", "[[" .. ref .. "\\|", "[[" .. ref .. "#", "](" .. ref .. ")", "](" .. ref .. "#" }
	end
	local from, to = {}, {}
	for _, pair in ipairs({ { old_id, new_id }, { old_rel, new_rel }, { old_rel .. ".md", new_rel .. ".md" } }) do
		vim.list_extend(from, forms(pair[1]))
		vim.list_extend(to, forms(pair[2]))
	end

	local args = { "rg", "-l", "-F", "--glob", "*.md", "--color=never" }
	for _, f in ipairs(from) do
		vim.list_extend(args, { "-e", f })
	end
	local res = vim.system(args, { cwd = root, text = true }):wait()
	if res.code ~= 0 then
		return 0, 0 -- 1 = no references; anything else = nothing we can safely do
	end

	local total, files = 0, 0
	for rel in res.stdout:gmatch("[^\n]+") do
		local abs = root .. "/" .. rel
		local b = vim.fn.bufnr(abs)
		local loaded = b ~= -1 and vim.api.nvim_buf_is_loaded(b)
		if b ~= buf then
			local lines = loaded and vim.api.nvim_buf_get_lines(b, 0, -1, false) or vim.fn.readfile(abs)
			local n = 0
			for i, line in ipairs(lines) do
				for k = 1, #from do
					local c
					line, c = replace_plain(line, from[k], to[k])
					n = n + c
				end
				lines[i] = line
			end
			if n > 0 then
				if loaded then
					vim.api.nvim_buf_set_lines(b, 0, -1, false, lines)
				else
					vim.fn.writefile(lines, abs)
				end
				total, files = total + n, files + 1
			end
		end
	end
	return total, files
end

--- Rename `buf`'s note after its H1. `force` skips the timestamp-id/public guards.
function M.rename(buf, force)
	local path = vim.api.nvim_buf_get_name(buf)
	if path == "" or not path:match("%.md$") then
		return
	end
	local vault = vim.fs.find(".obsidian", { path = vim.fs.dirname(path), upward = true, type = "directory", limit = 1 })[1]
	if not vault then
		return
	end
	local root = vim.fs.dirname(vault)
	local stem = vim.fn.fnamemodify(path, ":t:r")
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

	local dir = vim.fs.dirname(path)
	local new_id, target = slug, dir .. "/" .. slug .. ".md"
	local n = 2
	-- (case-only renames are the same file on macOS, not a collision)
	while exists(target) and target:lower() ~= path:lower() do
		new_id = slug .. "-" .. n
		target = dir .. "/" .. new_id .. ".md"
		n = n + 1
	end

	local ok, err = vim.uv.fs_rename(path, target)
	if not ok then
		return vim.notify("NoteRename: could not rename: " .. tostring(err), vim.log.levels.ERROR)
	end

	local old_id = info.id or stem
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

	local rel = function(p)
		return (p:sub(#root + 2):gsub("%.md$", ""))
	end
	local refs, files = update_backlinks(root, buf, old_id, new_id, rel(path), rel(target))
	vim.notify(
		("Renamed %s.md → %s.md%s"):format(stem, new_id, refs > 0 and (" (%d link%s in %d file%s)"):format(refs, refs == 1 and "" or "s", files, files == 1 and "" or "s") or ""),
		vim.log.levels.INFO
	)
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

vim.api.nvim_create_user_command("NoteRenameFromTitle", function()
	M.rename(vim.api.nvim_get_current_buf(), true)
end, { desc = "Rename the current note to the dash-case of its # title" })

return M
