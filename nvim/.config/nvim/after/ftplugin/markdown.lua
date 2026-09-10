-- Markdown indent: make `>`/`<` shift by 2 spaces (not 4).
-- after/ftplugin loads last, so this overrides any plugin/runtime ftplugin
-- that bumps shiftwidth to 4 for markdown buffers.
vim.bo.expandtab = true
vim.bo.shiftwidth = 2
vim.bo.tabstop = 2
vim.bo.softtabstop = 2

-- ---------------------------------------------------------------------------
-- Markdown text objects
-- ---------------------------------------------------------------------------
-- Vim ships text objects for quotes and brackets but knows nothing about
-- markdown's own delimiters, so `di*` inside **bold** used to fall through to
-- "delete to the next *", which is never what you want.
--
-- Convention throughout (the same one Vim uses for `i"` / `a"`):
--   i<x> = the CONTENT between the delimiters
--   a<x> = the content AND the delimiters
-- `a` deliberately does NOT swallow surrounding whitespace -- `ca*` to retype a
-- bold run is the common case, and eating the space breaks the sentence.
--
--   i*  a*   **bold**      (falls back to *italic* when there is no ** pair)
--   i_  a_   __bold__      (falls back to _italic_)
--   i`  a`   `inline code`
--   i~  a~   ~~strikethrough~~
--   i$  a$   $math$        (tries $$display math$$ first)
--   il  al   [text](url)   -- and [[wikilink|alias]]
--   iu  au   the url/target of the link under the cursor
--   ic  ac   ``` fenced code block ```    (linewise)
--   ih  ah   heading section              (linewise)
--
-- All maps are buffer-local, so no other filetype is affected.

local map = function(lhs, fn, desc)
	vim.keymap.set({ "x", "o" }, lhs, fn, { buffer = true, silent = true, desc = desc })
end

-- Return the 1-indexed byte columns of every occurrence of the literal `delim`
-- in `line`. When `avoid_run` is set, occurrences that are part of a LONGER run
-- of the same character are skipped -- that is what lets the single-`*` pass
-- ignore the `*`s that belong to a `**bold**` pair.
local function scan(line, delim, avoid_run)
	local out, dlen, i = {}, #delim, 1
	local c = delim:sub(1, 1)
	while true do
		local s = line:find(delim, i, true)
		if not s then
			return out
		end
		local in_run = avoid_run and (line:sub(s - 1, s - 1) == c or line:sub(s + dlen, s + dlen) == c)
		if in_run then
			i = s + 1
		else
			out[#out + 1] = s
			i = s + dlen
		end
	end
end

-- Pair the occurrences off in order (1st-2nd, 3rd-4th, ...) and return the pair
-- enclosing `col`, so `**a** **b**` resolves to whichever run the cursor is in.
local function span_at(line, col, delim, avoid_run)
	local pos = scan(line, delim, avoid_run)
	local dlen = #delim
	for k = 1, #pos - 1, 2 do
		local o, c = pos[k], pos[k + 1]
		if col >= o and col <= c + dlen - 1 then
			return {
				outer_s = o,
				outer_e = c + dlen - 1,
				inner_s = o + dlen,
				inner_e = c - 1,
			}
		end
	end
end

-- Enter charwise visual over the region. Works from both visual and
-- operator-pending mode: the operator applies to whatever we leave selected.
local function select_region(sr, sc, er, ec)
	if vim.fn.mode():match("[vV\22]") then
		vim.cmd("normal! \27")
	end
	vim.fn.setpos(".", { 0, sr, sc, 0 })
	vim.cmd("normal! v")
	vim.fn.setpos(".", { 0, er, ec, 0 })
	if vim.o.selection == "exclusive" then
		vim.cmd("normal! l")
	end
end

local function select_lines(sr, er)
	if vim.fn.mode():match("[vV\22]") then
		vim.cmd("normal! \27")
	end
	vim.fn.setpos(".", { 0, sr, 1, 0 })
	vim.cmd("normal! V")
	vim.fn.setpos(".", { 0, er, 1, 0 })
end

-- Build the i/a pair for a delimiter, trying candidates longest-first so
-- `**bold**` wins over `*italic*` when the cursor sits inside both readings.
local function delim_objects(lhs, candidates, desc)
	local function resolve()
		local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
		local line = vim.api.nvim_get_current_line()
		local col = col0 + 1
		for _, d in ipairs(candidates) do
			-- avoid_run only matters for the single-character fallback
			local span = span_at(line, col, d, #d == 1)
			if span then
				return row, span
			end
		end
	end

	map("i" .. lhs, function()
		local row, s = resolve()
		-- An empty span (`****`) has nothing inside to operate on.
		if not s or s.inner_e < s.inner_s then
			return
		end
		select_region(row, s.inner_s, row, s.inner_e)
	end, "inner " .. desc)

	map("a" .. lhs, function()
		local row, s = resolve()
		if not s then
			return
		end
		select_region(row, s.outer_s, row, s.outer_e)
	end, "a " .. desc)
end

delim_objects("*", { "**", "*" }, "bold/italic (*)")
delim_objects("_", { "__", "_" }, "bold/italic (_)")
delim_objects("`", { "`" }, "inline code")
delim_objects("~", { "~~", "~" }, "strikethrough")
delim_objects("$", { "$$", "$" }, "math")

-- --- Links -----------------------------------------------------------------
-- `%b[]` matches balanced brackets, so it survives [text with [nested] bits].
local function link_at(line, col)
	local init = 1
	while true do
		local s, e = line:find("%b[]%b()", init)
		if not s then
			break
		end
		if col >= s and col <= e then
			local _, be = line:find("%b[]", s)
			return {
				outer_s = s,
				outer_e = e,
				text_s = s + 1,
				text_e = be - 1,
				url_s = be + 2,
				url_e = e - 1,
			}
		end
		init = e + 1
	end

	-- Wiki links: [[target]] or [[target|alias]]. Inner prefers the alias,
	-- since that is the part you actually read and retype.
	init = 1
	while true do
		local s, e = line:find("%[%[.-%]%]", init)
		if not s then
			return nil
		end
		if col >= s and col <= e then
			local body_s, body_e = s + 2, e - 2
			local body = line:sub(body_s, body_e)
			local bar = body:find("|", 1, true)
			return {
				outer_s = s,
				outer_e = e,
				text_s = bar and (body_s + bar) or body_s,
				text_e = body_e,
				url_s = body_s,
				url_e = bar and (body_s + bar - 2) or body_e,
			}
		end
		init = e + 1
	end
end

local function link_object(lhs, sfield, efield, desc)
	map(lhs, function()
		local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
		local l = link_at(vim.api.nvim_get_current_line(), col0 + 1)
		if not l or l[efield] < l[sfield] then
			return
		end
		select_region(row, l[sfield], row, l[efield])
	end, desc)
end

link_object("il", "text_s", "text_e", "inner link text")
link_object("al", "outer_s", "outer_e", "a whole link")
link_object("iu", "url_s", "url_e", "inner link url/target")
link_object("au", "outer_s", "outer_e", "a whole link (url)")

-- --- Follow link (<CR> / gd) -------------------------------------------------
-- Works anywhere the cursor sits on a [text](target) or [[wikilink]] -- unlike
-- built-in gf, which needs the cursor on the path itself. Targets resolve
-- relative to THIS FILE's directory (gf uses cwd), URLs open in the browser,
-- and #anchors jump to the matching heading. obsidian.nvim only maps its
-- follower inside the vault workspace, so this covers every other repo too.

-- Jump to the heading a GitHub-style #anchor points at ("#build-order" ->
-- "## Build order"). Slug rule: lowercase, punctuation dropped, spaces -> "-".
local function goto_anchor(slug)
	slug = slug:lower()
	for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
		local h = l:match("^#+%s+(.+)")
		if h and h:lower():gsub("[^%w%s%-]", ""):gsub("%s", "-") == slug then
			vim.cmd("normal! m'") -- keep <C-o> working back to the link
			vim.api.nvim_win_set_cursor(0, { i, 0 })
			return true
		end
	end
	return false
end

local function follow_link()
	local col0 = vim.api.nvim_win_get_cursor(0)[2]
	local line = vim.api.nvim_get_current_line()
	local l = link_at(line, col0 + 1)
	if not l or l.url_e < l.url_s then
		return false
	end
	local target = line:sub(l.url_s, l.url_e):match("^<?(.-)>?$"):gsub("%%20", " ")

	if target:match("^%a[%w+.-]*://") or target:match("^www%.") then
		vim.ui.open(target)
		return true
	end
	if target:sub(1, 1) == "#" then
		return goto_anchor(target:sub(2))
	end

	local path, anchor = target:match("^([^#]*)#?(.*)$")
	if path:sub(1, 1) ~= "/" and path:sub(1, 1) ~= "~" then
		path = vim.fs.joinpath(vim.fn.expand("%:p:h"), path)
	end
	path = vim.fn.fnamemodify(path, ":p")
	-- Wikilink targets usually omit the extension.
	if vim.fn.filereadable(path) == 0 and vim.fn.filereadable(path .. ".md") == 1 then
		path = path .. ".md"
	end
	vim.cmd.edit(vim.fn.fnameescape(path))
	if anchor ~= "" then
		goto_anchor(anchor)
	end
	return true
end

-- Fall back to the keys' normal jobs when the cursor is not on a link.
vim.keymap.set("n", "<CR>", function()
	if not follow_link() then
		vim.cmd("normal! j^")
	end
end, { buffer = true, silent = true, desc = "Follow markdown link" })
vim.keymap.set("n", "gd", function()
	if not follow_link() then
		vim.cmd("normal! gd")
	end
end, { buffer = true, silent = true, desc = "Follow markdown link" })

-- --- Fenced code blocks (linewise) ------------------------------------------
local function is_fence(l)
	return l ~= nil and (l:match("^%s*```") ~= nil or l:match("^%s*~~~") ~= nil)
end

local function fence_at(row)
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	-- Walk up to the opening fence; the cursor may sit ON either fence line.
	local top
	for i = row, 1, -1 do
		if is_fence(lines[i]) then
			top = i
			break
		end
	end
	if not top then
		return nil
	end

	local bottom
	for i = top + 1, #lines do
		if is_fence(lines[i]) then
			bottom = i
			break
		end
	end
	-- No closing fence, or the cursor was below a block that already closed.
	if not bottom or row > bottom then
		return nil
	end
	return top, bottom
end

map("ic", function()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local top, bottom = fence_at(row)
	if not top or bottom - top < 2 then
		return
	end
	select_lines(top + 1, bottom - 1)
end, "inner code fence")

map("ac", function()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local top, bottom = fence_at(row)
	if not top then
		return
	end
	select_lines(top, bottom)
end, "a code fence")

-- --- Heading sections (linewise) --------------------------------------------
-- `ah` = the heading and everything under it, stopping at the next heading of
-- the same or higher level -- so `dah` on a `##` takes its `###` children too.
local function section_at(row)
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local level_of = function(l)
		local h = l and l:match("^(#+)%s")
		return h and #h or nil
	end

	local top, level
	for i = row, 1, -1 do
		local lv = level_of(lines[i])
		if lv then
			top, level = i, lv
			break
		end
	end
	if not top then
		return nil
	end

	local bottom = #lines
	for i = top + 1, #lines do
		local lv = level_of(lines[i])
		if lv and lv <= level then
			bottom = i - 1
			break
		end
	end
	return top, bottom
end

map("ih", function()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local top, bottom = section_at(row)
	if not top or bottom <= top then
		return
	end
	select_lines(top + 1, bottom)
end, "inner heading section (body only)")

map("ah", function()
	local row = vim.api.nvim_win_get_cursor(0)[1]
	local top, bottom = section_at(row)
	if not top then
		return
	end
	select_lines(top, bottom)
end, "a heading section (with heading)")

-- ---------------------------------------------------------------------------
-- List conversion
-- ---------------------------------------------------------------------------
-- Turn the selected lines (or the current line) into a list, or back:
--   <leader>ln  numbered    <leader>lb  bullets    <leader>lt  todos
--   <leader>lc  strip markers
-- Pressing a map whose kind the lines ALREADY are toggles the markers off.
-- Also a range command for scripts/muscle memory: :'<,'>MdList number
-- Blank lines inside the range are left alone, so a selection spanning
-- paragraphs numbers only the text lines.

local function line_kind(l)
	if l:match("^%s*$") then
		return "blank"
	end
	if l:match("^%s*[-*+]%s+%[.%]") then
		return "todo"
	end
	if l:match("^%s*[-*+]%s") then
		return "bullet"
	end
	if l:match("^%s*%d+[.)]%s") then
		return "number"
	end
	return "plain"
end

local function strip_marker(l)
	local indent, rest = l:match("^(%s*)(.*)$")
	rest = rest:gsub("^[-*+]%s+%[.%]%s*", ""):gsub("^[-*+]%s+", ""):gsub("^%d+[.)]%s+", "")
	return indent, rest
end

local function convert(s, e, kind)
	local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
	if kind ~= "clear" then
		-- Uniformly this kind already? Then the second press means "undo it".
		local all = true
		for _, l in ipairs(lines) do
			local k = line_kind(l)
			if k ~= "blank" and k ~= kind then
				all = false
				break
			end
		end
		if all then
			kind = "clear"
		end
	end
	local n = 0
	for i, l in ipairs(lines) do
		if line_kind(l) ~= "blank" then
			local indent, rest = strip_marker(l)
			if kind == "number" then
				n = n + 1
				lines[i] = indent .. n .. ". " .. rest
			elseif kind == "bullet" then
				lines[i] = indent .. "- " .. rest
			elseif kind == "todo" then
				lines[i] = indent .. "- [ ] " .. rest
			else
				lines[i] = indent .. rest
			end
		end
	end
	vim.api.nvim_buf_set_lines(0, s - 1, e, false, lines)
end

local LIST_KINDS = { number = true, bullet = true, todo = true, clear = true }

vim.api.nvim_buf_create_user_command(0, "MdList", function(o)
	local kind = o.args ~= "" and o.args or "bullet"
	if not LIST_KINDS[kind] then
		vim.notify("MdList: unknown kind `" .. kind .. "`", vim.log.levels.ERROR)
		return
	end
	convert(o.line1, o.line2, kind)
end, {
	range = true,
	nargs = "?",
	complete = function()
		return { "number", "bullet", "todo", "clear" }
	end,
})

local function list_map(lhs, kind, desc)
	vim.keymap.set({ "n", "x" }, lhs, function()
		local s, e
		if vim.fn.mode():match("[vV\22]") then
			vim.cmd("normal! \27")
			s, e = vim.fn.line("'<"), vim.fn.line("'>")
		else
			s = vim.fn.line(".")
			e = s
		end
		convert(s, e, kind)
	end, { buffer = true, silent = true, desc = desc })
end

list_map("<leader>ln", "number", "Lines → numbered list (toggle)")
list_map("<leader>lb", "bullet", "Lines → bullet list (toggle)")
list_map("<leader>lt", "todo", "Lines → todo list (toggle)")
list_map("<leader>lc", "clear", "Remove list markers")

-- ---------------------------------------------------------------------------
-- Inline markdown formatting (VISUAL mode)
-- ---------------------------------------------------------------------------
-- Select text, hit a <leader>m map, and the selection is wrapped in the
-- markdown syntax for it. Every inline map TOGGLES: press it on text that is
-- already wrapped and the delimiters come off, so the same key both applies
-- and removes.
--
--   <leader>mpl  [sel](url-from-clipboard)   -- "paste link", the fast path
--   <leader>ml   [sel]()  + insert mode inside the parens
--   <leader>mw   [[sel]]                     -- Obsidian wiki link
--   <leader>mu   bare [sel](sel) when sel IS a url -- autolink it
--   <leader>mb   **sel**
--   <leader>mi   *sel*
--   <leader>m`   `sel`
--   <leader>ms   ~~sel~~
--   <leader>mh   ==sel==
--   <leader>m$   $sel$
--   <leader>mq   > sel        (linewise, toggle)
--   <leader>mf   ```fence```  (linewise, toggle)
--
-- VISUAL ONLY, on purpose. <leader>m is a busy prefix in normal mode --
-- nabla owns <leader>mm/<leader>mp in markdown buffers, molten owns
-- <leader>mi/<leader>me, iron owns <leader>mc/<leader>md. Buffer-local maps
-- beat global ones, so claiming normal-mode <leader>m here would silently
-- shadow nabla's math rendering in exactly the buffers it exists for. In
-- visual mode those are free (iron's <leader>mc visual mark is the only
-- overlap, and `mc` is deliberately not used below).

-- Run `fn` over the visual selection and replace it with what comes back.
--
-- Done through a register + `gv` rather than nvim_buf_set_text with the '< '>
-- marks: the marks store a BYTE column for the first byte of the last char, so
-- reconstructing an exclusive end offset splits multibyte characters (every
-- em-dash and → in this vault). Yank/paste has no such problem, and it gets
-- charwise vs linewise vs blockwise right for free.
--
-- Returning nil from `fn` cancels and leaves the buffer untouched.
local function transform_selection(fn, then_insert)
	local save_z = vim.fn.getreginfo("z")
	local save_unnamed = vim.fn.getreginfo('"')
	local restore = function()
		vim.fn.setreg("z", save_z)
		vim.fn.setreg('"', save_unnamed)
	end

	vim.cmd('noautocmd silent normal! "zy')
	local info = vim.fn.getreginfo("z")
	local linewise = info.regtype == "V"
	local text = table.concat(info.regcontents or {}, "\n")

	-- Whitespace the selection accidentally swept up stays OUTSIDE the
	-- delimiters. Selecting a word with `vw` or an extra `l` is the normal way
	-- to miss, and `**bold **` is not bold -- CommonMark refuses to close an
	-- emphasis run on a space, so the sloppy selection would silently produce
	-- literal asterisks in the rendered doc.
	local lead, core, trail = text:match("^(%s*)(.-)(%s*)$")
	if core == "" then
		restore()
		return
	end

	local new = fn(core)
	if new == nil then
		restore()
		return
	end
	new = lead .. new .. trail

	vim.fn.setreg("z", new, linewise and "V" or "v")
	vim.cmd('noautocmd silent normal! gv"zp')
	restore()

	if then_insert then
		-- `p` in visual mode leaves the cursor on the LAST pasted character and
		-- `startinsert` inserts before the cursor, so landing on the closing `)`
		-- puts typing inside the parens. Step back over any trailing whitespace
		-- we re-attached, or the cursor sits past the `)` and the url is typed
		-- outside the link.
		if #trail > 0 then
			vim.cmd("normal! " .. #trail .. "h")
		end
		vim.cmd("startinsert")
	end
end

local function fmt_map(lhs, fn, desc, then_insert)
	vim.keymap.set("x", lhs, function()
		transform_selection(fn, then_insert)
	end, { buffer = true, silent = true, desc = desc })
end

-- Wrap in `pre`/`post`, or unwrap when it is already wrapped.
local function toggle_wrap(pre, post)
	post = post or pre
	return function(text)
		if #text >= #pre + #post and text:sub(1, #pre) == pre and text:sub(-#post) == post then
			return text:sub(#pre + 1, #text - #post)
		end
		return pre .. text .. post
	end
end

local function looks_like_url(s)
	return s:match("^%a[%w+.-]*://%S+$") ~= nil or s:match("^www%.%S+$") ~= nil or s:match("^mailto:%S+$") ~= nil
end

-- The clipboard, trimmed. Newlines are stripped rather than kept: a URL copied
-- out of a browser often arrives with a trailing \n, and pasting that into
-- `[text](...)` splits the link across two lines and silently breaks it.
local function clipboard_url()
	for _, reg in ipairs({ "+", "*" }) do
		local v = vim.fn.getreg(reg)
		if type(v) == "string" then
			v = v:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
			if v ~= "" then
				return v
			end
		end
	end
	return nil
end

fmt_map("<leader>mpl", function(text)
	local url = clipboard_url()
	if not url then
		vim.notify("clipboard is empty — nothing to link to", vim.log.levels.WARN)
		return nil
	end
	if not looks_like_url(url) then
		-- Not fatal: relative paths and note names are legitimate link targets.
		-- Say so once so a mis-copy is visible instead of silently wrong.
		vim.notify("linking to a non-URL clipboard value: " .. url, vim.log.levels.WARN)
	end
	return "[" .. text .. "](" .. url .. ")"
end, "Markdown: selection → link, url from clipboard")

fmt_map("<leader>ml", function(text)
	return "[" .. text .. "]()"
end, "Markdown: selection → link, type the url", true)

fmt_map("<leader>mw", toggle_wrap("[[", "]]"), "Markdown: selection → wiki link (toggle)")

fmt_map("<leader>mu", function(url)
	if not looks_like_url(url) then
		vim.notify("selection is not a url — use <leader>mpl or <leader>ml", vim.log.levels.WARN)
		return nil
	end
	return "[" .. url .. "](" .. url .. ")"
end, "Markdown: url → self-titled link")

fmt_map("<leader>mb", toggle_wrap("**"), "Markdown: bold (toggle)")
fmt_map("<leader>mi", toggle_wrap("*"), "Markdown: italic (toggle)")
fmt_map("<leader>m`", toggle_wrap("`"), "Markdown: inline code (toggle)")
fmt_map("<leader>ms", toggle_wrap("~~"), "Markdown: strikethrough (toggle)")
fmt_map("<leader>mh", toggle_wrap("=="), "Markdown: highlight (toggle)")
fmt_map("<leader>m$", toggle_wrap("$"), "Markdown: inline math (toggle)")

-- Linewise. These reshape whole lines, so they run off the line range rather
-- than the character selection.
local function linewise_map(lhs, fn, desc)
	vim.keymap.set("x", lhs, function()
		vim.cmd("normal! \27")
		local s, e = vim.fn.line("'<"), vim.fn.line("'>")
		local lines = vim.api.nvim_buf_get_lines(0, s - 1, e, false)
		local new = fn(lines)
		if new then
			vim.api.nvim_buf_set_lines(0, s - 1, e, false, new)
		end
	end, { buffer = true, silent = true, desc = desc })
end

linewise_map("<leader>mq", function(lines)
	-- Already a quote throughout? Then the second press unquotes.
	local all = true
	for _, l in ipairs(lines) do
		if not l:match("^%s*>") and not l:match("^%s*$") then
			all = false
			break
		end
	end
	local out = {}
	for i, l in ipairs(lines) do
		if all then
			out[i] = (l:gsub("^(%s*)>%s?", "%1"))
		else
			out[i] = l:match("^%s*$") and ">" or ("> " .. l)
		end
	end
	return out
end, "Markdown: blockquote (toggle)")

linewise_map("<leader>mf", function(lines)
	-- Unfence when the selection is exactly a fenced block already.
	if #lines >= 2 and lines[1]:match("^%s*```") and lines[#lines]:match("^%s*```%s*$") then
		return vim.list_slice(lines, 2, #lines - 1)
	end
	local out = { "```" }
	vim.list_extend(out, lines)
	table.insert(out, "```")
	return out
end, "Markdown: fenced code block (toggle)")
