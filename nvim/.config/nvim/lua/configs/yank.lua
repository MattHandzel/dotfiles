-- <leader>y — yank the *identity* of the thing under the cursor.
--
-- The recurring friction this removes: to link one note to another, or to hand
-- Claude a file reference, you had to read a value off the screen and retype it.
-- Every map here puts one such value straight on the system clipboard.
--
-- Two tiers:
--   universal  — work in any buffer (paths, line refs, URLs)
--   note       — buffer-local to markdown, since they read vault frontmatter
--
-- Every yank also fills the unnamed register, so `p` pastes it inside nvim
-- without round-tripping through the system clipboard.

local M = {}

-- --- plumbing ---------------------------------------------------------------

local function copy(value, label)
	if not value or value == "" then
		vim.notify("Nothing to yank: " .. label, vim.log.levels.WARN, { title = "Yank" })
		return
	end
	vim.fn.setreg("+", value)
	vim.fn.setreg('"', value)
	-- One-line preview. Long values get elided rather than wrapping the cmdline
	-- into a hit-enter prompt, which is its own small tax on a hotkey you press
	-- dozens of times a day.
	local preview = value:gsub("\n", " ")
	if #preview > 60 then
		preview = preview:sub(1, 57) .. "..."
	end
	vim.notify(preview, vim.log.levels.INFO, { title = "Yanked " .. label })
end

local function buf_lines(buf, last)
	return vim.api.nvim_buf_get_lines(buf, 0, last or -1, false)
end

-- --- vault / frontmatter ----------------------------------------------------

--- Value of a frontmatter scalar key, or nil.
--- Reads the buffer directly instead of vim.fn.search() so the cursor never
--- moves and the map is safe to press from anywhere in the file.
local function frontmatter(buf, key)
	local lines = buf_lines(buf, 200)
	if lines[1] ~= "---" then
		return nil
	end
	for i = 2, #lines do
		local line = lines[i]
		if line == "---" or line == "..." then
			return nil -- end of frontmatter, key absent
		end
		local value = line:match("^" .. key .. ":%s*(.*)$")
		if value then
			-- Strip surrounding quotes: obsidian.nvim writes dates as "2026-08-10".
			value = value:gsub("^[\"']", ""):gsub("[\"']$", "")
			return vim.trim(value)
		end
	end
	return nil
end

--- First entry of the frontmatter `aliases:` list, or nil.
local function first_alias(buf)
	local lines = buf_lines(buf, 200)
	if lines[1] ~= "---" then
		return nil
	end
	local in_aliases = false
	for i = 2, #lines do
		local line = lines[i]
		if line == "---" or line == "..." then
			return nil
		end
		if in_aliases then
			local item = line:match("^%s*%-%s*(.+)$")
			if not item then
				return nil -- list ended without an entry
			end
			item = item:gsub("^[\"']", ""):gsub("[\"']$", "")
			return vim.trim(item)
		end
		if line:match("^aliases:") then
			-- Inline form: `aliases: [A, B]`
			local inline = line:match("^aliases:%s*%[(.+)%]")
			if inline then
				local first = inline:match("^%s*([^,]+)")
				if first then
					return vim.trim((first:gsub("^[\"']", ""):gsub("[\"']$", "")))
				end
				return nil
			end
			in_aliases = true
		end
	end
	return nil
end

--- The note id. Falls back to the filename stem, which is what the vault's own
--- convention makes the id anyway -- so a note whose frontmatter has not been
--- written yet still yields a usable link instead of an error.
local function note_id(buf)
	return frontmatter(buf, "id") or vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t:r")
end

--- Human-facing title: the H1 if there is one, else the first alias, else the id.
local function note_title(buf)
	for _, line in ipairs(buf_lines(buf, 60)) do
		local h1 = line:match("^#%s+(.+)$")
		if h1 then
			return vim.trim(h1)
		end
	end
	return first_alias(buf) or note_id(buf)
end

--- Text of the nearest heading at or above the cursor, or nil.
local function heading_above_cursor()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local lines = buf_lines(0)
	for i = row, 1, -1 do
		local text = lines[i] and lines[i]:match("^#+%s+(.+)$")
		if text then
			return vim.trim(text)
		end
	end
	return nil
end

-- --- paths ------------------------------------------------------------------

--- Root to make paths relative to: the vault (.obsidian) if we are in one,
--- else the git repo, else nil. Vault wins because a vault-relative path is
--- what pastes usefully into a note, a Linear card, or a Claude prompt.
local function project_root(path)
	local vault = vim.fs.find(".obsidian", { path = path, upward = true, type = "directory" })[1]
	if vault then
		return vim.fs.dirname(vault)
	end
	local git = vim.fs.find(".git", { path = path, upward = true })[1]
	if git then
		return vim.fs.dirname(git)
	end
	return nil
end

local function abs_path(buf)
	local name = vim.api.nvim_buf_get_name(buf or 0)
	return name ~= "" and name or nil
end

local function rel_path(buf)
	local abs = abs_path(buf)
	if not abs then
		return nil
	end
	local root = project_root(abs)
	if not root then
		return vim.fn.fnamemodify(abs, ":~") -- best effort: home-relative
	end
	return abs:sub(#root + 2)
end

-- --- URLs -------------------------------------------------------------------

--- The URL under (or, failing that, first on) the cursor line. Markdown
--- `[text](url)` targets win over bare URLs, since in a note the bare-URL scan
--- would otherwise grab the link's own text.
local function url_at_cursor()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1

	local from = 1
	while true do
		local s, e, target = line:find("%[.-%]%((.-)%)", from)
		if not s then
			break
		end
		if col >= s and col <= e then
			return target
		end
		from = e + 1
	end

	from = 1
	while true do
		local s, e, url = line:find("(%a[%w+.-]*://[^%s)%]\"'>]+)", from)
		if not s then
			break
		end
		if col >= s and col <= e then
			return url
		end
		from = e + 1
	end

	-- Cursor was not on a link; fall back to the first one on the line.
	return line:match("%[.-%]%((.-)%)") or line:match("%a[%w+.-]*://[^%s)%]\"'>]+")
end

-- --- rich text --------------------------------------------------------------

--- Markdown with its YAML frontmatter removed.
--- pandoc would swallow a well-formed block as metadata anyway, but a vault
--- note's frontmatter is not always well-formed YAML (unquoted wikilinks, stray
--- colons), and a parse error there would fail the whole conversion.
local function strip_frontmatter(markdown)
	if not markdown:match("^%-%-%-\n") then
		return markdown
	end
	local body = markdown:match("^%-%-%-\n.-\n%-%-%-\n(.*)$") or markdown:match("^%-%-%-\n.-\n%.%.%.\n(.*)$")
	return body or markdown
end

--- Put HTML on the system clipboard as a *flavour*, not as text.
--- This is the whole point of the map: Substack, Gmail and Docs paste formatted
--- text when the clipboard carries an HTML flavour, and literal `<h1>` tags when
--- it carries the same HTML as plain text. `markdown` rides along as the
--- plain-text flavour so a paste into a terminal, or back into a note, still
--- gets something sensible instead of nothing.
local function set_clipboard_html(html, markdown)
	if vim.fn.has("mac") == 1 then
		-- macOS has no pbcopy equivalent of `wl-copy -t text/html`: pbcopy writes
		-- one flavour and cannot be told to write public.html. AppleScript can,
		-- via a hex `«data HTML...»` literal. The script goes through a file
		-- rather than `osascript -e` because that literal is as long as the
		-- document and would blow the argument limit on a long note.
		local hex = (html:gsub(".", function(c)
			return string.format("%02x", string.byte(c))
		end))
		local md_file, scpt = vim.fn.tempname(), vim.fn.tempname() .. ".scpt"
		vim.fn.writefile(vim.split(markdown, "\n"), md_file)
		vim.fn.writefile({
			("set h to «data HTML%s»"):format(hex),
			('set t to (read POSIX file "%s" as «class utf8»)'):format(md_file),
			"set the clipboard to {«class HTML»:h, string:t}",
		}, scpt)
		local res = vim.system({ "osascript", scpt }, { text = true }):wait()
		vim.fn.delete(md_file)
		vim.fn.delete(scpt)
		if res.code ~= 0 then
			return false, vim.trim(res.stderr ~= "" and res.stderr or "osascript failed")
		end
		return true
	end

	-- Wayland: one flavour only, same as the `md2substack` alias.
	if vim.fn.executable("wl-copy") == 1 then
		local res = vim.system({ "wl-copy", "-t", "text/html" }, { stdin = html, text = true }):wait()
		if res.code ~= 0 then
			return false, vim.trim(res.stderr ~= "" and res.stderr or "wl-copy failed")
		end
		return true
	end

	return false, "no HTML-capable clipboard tool (need osascript or wl-copy)"
end

--- Convert `markdown` to HTML and put it on the clipboard as rich text.
local function copy_as_html(markdown, label)
	markdown = vim.trim(strip_frontmatter(markdown or ""))
	if markdown == "" then
		copy(nil, label)
		return
	end
	if vim.fn.executable("pandoc") ~= 1 then
		vim.notify("pandoc is not on PATH", vim.log.levels.ERROR, { title = "Yank" })
		return
	end

	local pandoc = vim.system({ "pandoc", "-f", "markdown", "-t", "html" }, { stdin = markdown, text = true }):wait()
	if pandoc.code ~= 0 then
		vim.notify("pandoc failed: " .. vim.trim(pandoc.stderr or ""), vim.log.levels.ERROR, { title = "Yank" })
		return
	end

	local ok, err = set_clipboard_html(pandoc.stdout or "", markdown)
	if not ok then
		vim.notify(err, vim.log.levels.ERROR, { title = "Yank" })
		return
	end

	-- The `+` register is deliberately left alone: writing to it would clobber
	-- the HTML flavour we just set with a plain-text one. `"` still gets the
	-- markdown, so `p` pastes it inside nvim.
	vim.fn.setreg('"', markdown)
	local count = select(2, markdown:gsub("\n", "")) + 1
	vim.notify(
		("%d line%s as HTML"):format(count, count == 1 and "" or "s"),
		vim.log.levels.INFO,
		{ title = "Yanked " .. label }
	)
end

--- The text of the current visual selection, or nil when it is empty.
local function visual_selection()
	local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
	return #lines > 0 and table.concat(lines, "\n") or nil
end

-- --- maps -------------------------------------------------------------------

local function map(lhs, fn, desc, opts, mode)
	opts = vim.tbl_extend("force", { desc = "Yank " .. desc, silent = true }, opts or {})
	vim.keymap.set(mode or "n", lhs, fn, opts)
end

--- Maps that make sense in any buffer.
local function universal_maps()
	map("<leader>yp", function()
		copy(abs_path(0), "absolute path")
	end, "absolute file path")

	map("<leader>yr", function()
		copy(rel_path(0), "relative path")
	end, "vault/repo-relative path")

	-- `path:line` is the form CLAUDE.md asks for in code references, and most
	-- terminals turn it into a clickable jump.
	map("<leader>yf", function()
		local rel = rel_path(0)
		if not rel then
			copy(nil, "file reference")
			return
		end
		copy(("%s:%d"):format(rel, vim.api.nvim_win_get_cursor(0)[1]), "file reference")
	end, "path:line reference")

	map("<leader>yc", function()
		copy(vim.trim(vim.api.nvim_get_current_line()), "line")
	end, "current line (trimmed)")

	map("<leader>yu", function()
		copy(url_at_cursor(), "URL")
	end, "URL under cursor")
end

--- Maps that read vault frontmatter, so: markdown buffers only.
local function note_maps(buf)
	local function bmap(lhs, fn, desc)
		map(lhs, fn, desc, { buffer = buf })
	end

	bmap("<leader>yi", function()
		copy(note_id(buf), "note id")
	end, "note id")

	bmap("<leader>yl", function()
		copy(("[[%s]]"):format(note_id(buf)), "wikilink")
	end, "wikilink [[id]]")

	bmap("<leader>yL", function()
		copy(("[[%s|%s]]"):format(note_id(buf), note_title(buf)), "wikilink")
	end, "wikilink with title [[id|Title]]")

	bmap("<leader>yh", function()
		local heading = heading_above_cursor()
		if not heading then
			copy(nil, "heading link (no heading above cursor)")
			return
		end
		copy(("[[%s#%s]]"):format(note_id(buf), heading), "heading link")
	end, "link to heading under cursor")

	-- Rich text, for pasting into Substack / Gmail / Docs. Normal mode takes the
	-- whole note (minus frontmatter), visual mode takes the selection. Same job
	-- as the shell's `md2substack` alias, without leaving the buffer.
	map("<leader>yH", function()
		copy_as_html(table.concat(buf_lines(buf), "\n"), "note")
	end, "note as rich text (HTML)", { buffer = buf })

	map("<leader>yH", function()
		local selection = visual_selection()
		-- Leave visual mode first, so the notify does not redraw over a
		-- selection that is about to disappear anyway.
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
		copy_as_html(selection, "selection")
	end, "selection as rich text (HTML)", { buffer = buf }, "x")

	bmap("<leader>yt", function()
		copy(note_title(buf), "note title")
	end, "note title")
end

function M.setup()
	universal_maps()

	-- clear = true keeps this idempotent under :ReloadConfig, which re-requires
	-- mappings and therefore re-runs this setup.
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("UserYankNoteMaps", { clear = true }),
		pattern = { "markdown" },
		callback = function(args)
			note_maps(args.buf)
		end,
		desc = "Buffer-local <leader>y note-identity yanks",
	})

	-- The autocmd only fires on future FileType events, so a reload mid-session
	-- would leave every already-open note without its maps.
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "markdown" then
			note_maps(b)
		end
	end
end

return M
