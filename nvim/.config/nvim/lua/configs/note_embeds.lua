-- Render Obsidian note embeds inline, as virtual lines under the embed.
--
--   ![[note]]              the whole note, minus its YAML frontmatter
--   ![[note#Heading]]      only that section: the heading down to the next
--                          heading of the same or a higher level. Nested
--                          ![[note#H2#H3]] narrows step by step, as Obsidian does.
--   ![[note#^block-id]]    only that paragraph / list item (with its children)
--   ![[#Heading]]          a section of the current note
--
-- Links resolve the way Obsidian resolves them: by file name anywhere in the
-- vault (a note in the same folder wins, then the shortest path), or by path
-- when the link has one. Image / PDF / Excalidraw embeds are skipped -- those
-- belong to image.nvim and render-markdown.
--
-- How much shows is per embed: <leader>oE on the line cycles
-- preview (first `max_lines` screen lines) -> full -> collapsed. The choice is
-- remembered for that link target in every note and across sessions
-- (stdpath("state")/note_embeds.json), so collapsing ![[2026-q4-goals]] in one
-- daily note collapses it in all of them. :NoteEmbeds off hides them all.
-- Defaults are in `M.defaults`; autocommands.lua passes overrides to setup().
--
-- Why virtual lines and not text in the buffer: the embedded text must never
-- reach the file on disk (Obsidian would show it twice, and the autosave would
-- write it). The cost is that the cursor skips over it -- follow the link to
-- edit the source. Lines are wrapped here because virtual lines do not
-- soft-wrap; Neovim just cuts them off at the window edge.

local M = {}

M.defaults = {
	enabled = true,
	-- Height of a preview, in screen lines after wrapping. 0 = no limit.
	max_lines = 12,
	-- Mode for an embed you have not cycled yet: "preview", "full", "collapsed".
	default_mode = "preview",
	-- Drop a whole-note embed's leading "# Title" line (the embed line already
	-- names the note). Section embeds always keep their heading.
	hide_title = false,
	-- Cap on the wrap width, for readability on wide windows. nil = window edge.
	max_width = 100,
	-- Vault root used when no .obsidian/ folder is found above the buffer.
	vault = "~/Obsidian/Main",
	bar = "▎",
	-- Same icons render-markdown puts on headings (plugins/init.lua).
	heading_icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
	-- Normal-mode key, markdown buffers in a vault only. false = no mapping.
	toggle_key = "<leader>oE",
}

M.config = vim.deepcopy(M.defaults)

local ns = vim.api.nvim_create_namespace("note_embeds")
local AUGROUP = "NoteEmbeds"
local STATE_FILE = vim.fn.stdpath("state") .. "/note_embeds.json"
local MODES = { "preview", "full", "collapsed" }

-- Attachment types Obsidian embeds as media rather than as note text.
local MEDIA = {}
for _, ext in ipairs({
	"png",
	"jpg",
	"jpeg",
	"gif",
	"webp",
	"svg",
	"bmp",
	"avif",
	"pdf",
	"mp3",
	"wav",
	"m4a",
	"ogg",
	"flac",
	"webm",
	"mp4",
	"mov",
	"mkv",
	"canvas",
	"excalidraw",
	"base",
}) do
	MEDIA[ext] = true
end

local strwidth = vim.api.nvim_strwidth

---------------------------------------------------------------- highlights --

local function define_hl()
	local links = {
		NoteEmbedBar = "FloatBorder",
		NoteEmbedMuted = "Comment",
		NoteEmbedWarn = "DiagnosticWarn",
		NoteEmbedLink = "@markup.link.label",
		NoteEmbedCode = "@markup.raw",
		NoteEmbedBold = "@markup.strong",
		NoteEmbedItalic = "@markup.italic",
		NoteEmbedStrike = "@markup.strikethrough",
		NoteEmbedMark = "Visual",
		NoteEmbedQuote = "@markup.quote",
		NoteEmbedList = "@markup.list",
		NoteEmbedChecked = "@markup.list.checked",
		NoteEmbedUnchecked = "@markup.list.unchecked",
	}
	for i = 1, 6 do
		links["NoteEmbedH" .. i] = "@markup.heading." .. i .. ".markdown"
	end
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target, default = true })
	end
	-- Foreground only: linking to Normal would paint Normal's background over
	-- windows that use a different one (NormalNC, winhighlight, transparency).
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	vim.api.nvim_set_hl(0, "NoteEmbedText", { fg = normal.fg, default = true })
end

------------------------------------------------------------ vault + index --

-- root -> { at = uv.now() of the build, by_name = { lowercase stem -> {rel} } }
local indexes = {}
-- path -> { ver, lines } for notes read from disk
local files = {}
-- body() results; see its cache key
local rendered, rendered_count = {}, 0

local function build_index(root)
	-- --no-ignore: Obsidian indexes notes the vault's .gitignore excludes
	-- (journal/, personal/, events/...). Hidden folders stay skipped, as in
	-- Obsidian -- that also keeps .claude/worktrees duplicates out.
	local ok, res = pcall(function()
		return vim.system({ "rg", "--files", "--no-ignore", "--glob", "*.md" }, { cwd = root, text = true }):wait()
	end)
	local list
	if ok and res.code == 0 then
		list = vim.split(res.stdout, "\n", { trimempty = true })
	else
		list = {}
		for _, f in ipairs(vim.fn.globpath(root, "**/*.md", false, true)) do
			table.insert(list, f:sub(#root + 2))
		end
	end
	local by_name = {}
	for _, rel in ipairs(list) do
		local stem = rel:match("([^/]+)%.md$")
		if stem then
			stem = stem:lower()
			by_name[stem] = by_name[stem] or {}
			table.insert(by_name[stem], rel)
		end
	end
	indexes[root] = { at = vim.uv.now(), by_name = by_name }
	return indexes[root]
end

local function lookup(idx, name, from_dir)
	local want = name:lower()
	local cands = idx.by_name[want:match("([^/]+)$")]
	if not cands then
		return nil
	end
	local has_path = want:find("/", 1, true)
	local list = {}
	for _, rel in ipairs(cands) do
		local stem = rel:lower():gsub("%.md$", "")
		if not has_path or stem == want or stem:sub(-#want - 1) == "/" .. want then
			table.insert(list, rel)
		end
	end
	local function dir(rel)
		return rel:match("^(.*)/") or ""
	end
	local function depth(rel)
		return select(2, rel:gsub("/", ""))
	end
	table.sort(list, function(a, b)
		local sa, sb = dir(a) == from_dir, dir(b) == from_dir
		if sa ~= sb then
			return sa
		end
		if depth(a) ~= depth(b) then
			return depth(a) < depth(b)
		end
		return a < b
	end)
	return list[1]
end

local function resolve(root, name, from, force)
	name = name:gsub("%.md$", "")
	local from_dir = from:sub(#root + 2):match("^(.*)/") or ""
	local idx = indexes[root] or build_index(root)
	local rel = lookup(idx, name, from_dir)
	-- A miss (or a stale hit) may just be a note created since the last build.
	if (not rel or force) and vim.uv.now() - idx.at > 10000 then
		idx = build_index(root)
		rel = lookup(idx, name, from_dir)
	end
	return rel and (root .. "/" .. rel) or nil
end

local function vault_root(buf)
	local cached = vim.b[buf].note_embeds_root
	if cached ~= nil then
		return cached ~= "" and cached or nil
	end
	local root = vim.fs.root(buf, ".obsidian")
	if not root then
		local fallback = vim.fs.normalize(M.config.vault)
		local name = vim.api.nvim_buf_get_name(buf)
		if name:sub(1, #fallback + 1) == fallback .. "/" then
			root = fallback
		end
	end
	vim.b[buf].note_embeds_root = root or ""
	return root
end

--- Lines of a note, plus a version string that changes whenever they do.
--- An open buffer wins over the file, so an embed follows unsaved edits.
local function source(path)
	for _, b in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == path then
			return vim.api.nvim_buf_get_lines(b, 0, -1, false), "b" .. b .. ":" .. vim.api.nvim_buf_get_changedtick(b)
		end
	end
	local st = vim.uv.fs_stat(path)
	if not st then
		return nil
	end
	local ver = ("f%d.%d:%d"):format(st.mtime.sec, st.mtime.nsec, st.size)
	local c = files[path]
	if not c or c.ver ~= ver then
		local ok, lines = pcall(vim.fn.readfile, path)
		if not ok then
			return nil
		end
		c = { ver = ver, lines = lines }
		files[path] = c
	end
	return c.lines, c.ver
end

---------------------------------------------------------------- extraction --

local function is_fence(l)
	return l:match("^%s*```") or l:match("^%s*~~~")
end

local function strip_frontmatter(lines)
	if not (lines[1] and lines[1]:match("^%-%-%-%s*$")) then
		return lines
	end
	for i = 2, #lines do
		if lines[i]:match("^%-%-%-%s*$") or lines[i]:match("^%.%.%.%s*$") then
			return vim.list_slice(lines, i + 1)
		end
	end
	return lines -- never closed, so not frontmatter
end

-- Obsidian matches heading links loosely: case and link/format punctuation
-- do not count.
local function norm(s)
	s = s:lower():gsub("[%[%]%*_`|^:%%#]", ""):gsub("%s+", " ")
	return vim.trim(s)
end

local function headings(lines)
	local out, fence = {}, false
	for i, l in ipairs(lines) do
		if is_fence(l) then
			fence = not fence
		elseif not fence then
			local hashes, text = l:match("^(#+)%s+(.-)%s*$")
			if hashes and #hashes <= 6 then
				table.insert(out, { row = i, level = #hashes, text = text })
			end
		end
	end
	return out
end

local function section(lines, sub)
	local hs = headings(lines)
	local lo, hi = 1, #lines
	for part in vim.gsplit(sub, "#", { plain = true }) do
		local want = norm(part)
		if want ~= "" then
			local found
			for _, h in ipairs(hs) do
				if h.row >= lo and h.row <= hi and norm(h.text) == want then
					found = h
					break
				end
			end
			if not found then
				return nil
			end
			local stop = hi
			for _, h in ipairs(hs) do
				if h.row > found.row and h.row <= hi and h.level <= found.level then
					stop = h.row - 1
					break
				end
			end
			lo, hi = found.row, stop
		end
	end
	return vim.list_slice(lines, lo, hi)
end

local function block(lines, id)
	local tail = "%s+%^" .. vim.pesc(id) .. "%s*$"
	local alone = "^%s*%^" .. vim.pesc(id) .. "%s*$"
	for i, l in ipairs(lines) do
		if l:match(alone) then
			-- An id on its own line names the block just above it.
			local j = i - 1
			while j > 1 and lines[j - 1]:match("%S") do
				j = j - 1
			end
			return vim.list_slice(lines, math.max(j, 1), i - 1)
		elseif l:match(tail) then
			local first = l:gsub(tail, "")
			local indent = #l:match("^%s*")
			if l:match("^%s*[-*+] ") or l:match("^%s*%d+[.)] ") then
				local out = { first }
				for k = i + 1, #lines do
					local lk = lines[k]
					if not lk:match("%S") or #lk:match("^%s*") <= indent then
						break
					end
					table.insert(out, lk)
				end
				return out
			end
			local j = i
			while j > 1 and lines[j - 1]:match("%S") and not lines[j - 1]:match("^#") do
				j = j - 1
			end
			local out = vim.list_slice(lines, j, i)
			out[#out] = first
			return out
		end
	end
end

--- Drop comments and block ids, expand tabs, squeeze blank runs.
local function clean(lines, whole_note)
	local text = table.concat(lines, "\n")
	text = text:gsub("<!%-%-.-%-%->", ""):gsub("%%%%.-%%%%", "")
	local out, blank = {}, true
	for l in vim.gsplit(text, "\n", { plain = true }) do
		l = l:gsub("\t", "    "):gsub("%s+%^[%w%-]+%s*$", ""):gsub("%s+$", "")
		if l == "" then
			if not blank then
				table.insert(out, "")
			end
			blank = true
		else
			table.insert(out, l)
			blank = false
		end
	end
	if out[#out] == "" then
		table.remove(out)
	end
	if whole_note and M.config.hide_title and out[1] and out[1]:match("^#%s") then
		table.remove(out, 1)
		if out[1] == "" then
			table.remove(out, 1)
		end
	end
	return out
end

---------------------------------------------------------------- formatting --

local function stack(base, hl)
	local t = { unpack(base) }
	t[#t + 1] = hl
	return t
end

--- Inline markdown -> { {text, hl_stack}, ... }, markup characters removed.
local function inline(text, base, out)
	out = out or {}
	local i, n, plain = 1, #text, 1
	local function flush(upto)
		if upto >= plain then
			table.insert(out, { text:sub(plain, upto), base })
		end
	end
	while i <= n do
		local c = text:sub(i, i)
		local e, a
		local matched = false
		if c == "!" or c == "[" then
			local s
			s, e, a = text:find("^!?%[%[(.-)%]%]", i)
			if s then
				flush(i - 1)
				local label = a:match("|(.*)$") or a
				table.insert(out, { (c == "!" and "󰈙 " or "") .. label, stack(base, "NoteEmbedLink") })
				matched = true
			elseif c == "[" then
				s, e, a = text:find("^%[([^%]]+)%]%([^)]*%)", i)
				if s then
					flush(i - 1)
					table.insert(out, { a, stack(base, "NoteEmbedLink") })
					matched = true
				end
			end
		elseif c == "`" then
			local s
			s, e, a = text:find("^`([^`]+)`", i)
			if s then
				flush(i - 1)
				table.insert(out, { a, stack(base, "NoteEmbedCode") })
				matched = true
			end
		elseif c == "*" or c == "_" or c == "=" or c == "~" then
			-- Only at a word start, so snake_case and 2*3*4 stay literal.
			if i == 1 or text:sub(i - 1, i - 1):match("[%s%p]") then
				local d = vim.pesc(c)
				local rules = {
					{
						"^" .. d .. d .. "(%S.-)" .. d .. d,
						(c == "=" and "NoteEmbedMark") or (c == "~" and "NoteEmbedStrike") or "NoteEmbedBold",
					},
				}
				if c == "*" or c == "_" then
					table.insert(rules, { "^" .. d .. "(%S[^" .. d .. "]-)" .. d, "NoteEmbedItalic" })
				end
				for _, r in ipairs(rules) do
					local s
					s, e, a = text:find(r[1], i)
					if s then
						flush(i - 1)
						inline(a, stack(base, r[2]), out)
						matched = true
						break
					end
				end
			end
		end
		if matched then
			i = e + 1
			plain = i
		else
			i = i + 1
		end
	end
	flush(n)
	return out
end

--- One source line -> segments + hanging indent for its wrapped continuation.
local function format_line(l, state)
	if is_fence(l) then
		state.fence = not state.fence
		return { { l, { "NoteEmbedText", "NoteEmbedCode" } } }, 0
	end
	if state.fence then
		return { { l, { "NoteEmbedText", "NoteEmbedCode" } } }, 0
	end
	if l:match("^%s*[-*_]%s*[-*_]%s*[-*_][-*_%s]*$") then
		return nil, 0, "rule"
	end

	local hashes, htext = l:match("^(#+)%s+(.*)$")
	if hashes and #hashes <= 6 then
		local hl = { "NoteEmbedText", "NoteEmbedH" .. #hashes }
		local icon = M.config.heading_icons[#hashes] or ""
		return inline(htext, hl, { { icon, hl } }), strwidth(icon)
	end

	local base = { "NoteEmbedText" }
	local segs = {}
	local q, rest = l:match("^(%s*)>%s?(.*)$")
	if q then
		table.insert(segs, { q .. "┃ ", { "NoteEmbedQuote" } })
		base = { "NoteEmbedText", "NoteEmbedQuote" }
		l = rest
		-- Callout header: > [!note]- Title  ->  ┃ 󰋽 Title
		local kind, title = l:match("^%[!([%w-]+)%][+-]?%s*(.*)$")
		if kind then
			local head = title ~= "" and title or (kind:sub(1, 1):upper() .. kind:sub(2))
			table.insert(segs, { "󰋽 ", stack(base, "NoteEmbedBold") })
			return inline(head, stack(base, "NoteEmbedBold"), segs), strwidth(q .. "┃ 󰋽 ")
		end
	end

	local ws, box, body = l:match("^(%s*)[-*+] %[(.)%]%s?(.*)$")
	if ws then
		local done = box ~= " "
		table.insert(
			segs,
			{ ws .. (done and "󰱒 " or "󰄱 "), { done and "NoteEmbedChecked" or "NoteEmbedUnchecked" } }
		)
		l = body
	else
		local ws2, body2 = l:match("^(%s*)[-*+]%s+(.*)$")
		if ws2 then
			table.insert(segs, { ws2 .. "• ", { "NoteEmbedList" } })
			l = body2
		else
			local ws3, num, body3 = l:match("^(%s*)(%d+[.)])%s+(.*)$")
			if ws3 then
				table.insert(segs, { ws3 .. num .. " ", { "NoteEmbedList" } })
				l = body3
			end
		end
	end

	local hang = 0
	for _, s in ipairs(segs) do
		hang = hang + strwidth(s[1])
	end
	return inline(l, base, segs), hang
end

-- Longest prefix of `s` that fits in `cols` display columns; at least one
-- character, so a caller looping on it always makes progress.
local function take_cols(s, cols)
	local out, w = {}, 0
	for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		local cw = strwidth(ch)
		if w + cw > cols and #out > 0 then
			break
		end
		out[#out + 1] = ch
		w = w + cw
		if w >= cols then
			break
		end
	end
	return table.concat(out)
end

--- Word-wrap segments to `width` columns. Returns a list of chunk lists.
local function wrap(segs, width, hang)
	local lines = {}
	local cur, w, has_text = {}, 0, false
	-- Whitespace between words is held until the next word is placed, so a
	-- line never ends in the space it broke at.
	local gap
	local function newline()
		table.insert(lines, cur)
		cur = hang > 0 and { { string.rep(" ", hang), "NoteEmbedText" } } or {}
		w, has_text, gap = hang, false, nil
	end
	local function put(text, hl, tw)
		cur[#cur + 1] = { text, hl }
		w = w + tw
	end
	for _, seg in ipairs(segs) do
		local hl = seg[2]
		for ws, word in seg[1]:gmatch("(%s*)(%S*)") do
			if ws ~= "" then
				if has_text then
					gap = { ws, hl, strwidth(ws) }
				elseif #lines == 0 then
					put(ws, hl, strwidth(ws)) -- the line's own indentation
				end
			end
			if word ~= "" then
				local ww = strwidth(word)
				if gap and w + gap[3] + ww <= width then
					put(gap[1], gap[2], gap[3])
				elseif gap or (has_text and w + ww > width and ww <= width - hang) then
					-- Also for a word glued to the previous chunk ("(" .. link):
					-- move it whole rather than split it mid-word.
					newline()
				end
				gap = nil
				while w + ww > width do
					if has_text and w >= width then
						newline()
					end
					local part = take_cols(word, width - w)
					put(part, hl, strwidth(part))
					has_text = true
					word = word:sub(#part + 1)
					ww = strwidth(word)
					if ww > 0 then
						newline()
					end
				end
				if ww > 0 then
					put(word, hl, ww)
					has_text = true
				end
			end
		end
	end
	table.insert(lines, cur)
	return lines
end

--- Display lines for one embed (chunk lists, before bar and indent), or
--- nil + a reason.
local function body(buf, root, e, width)
	local from = vim.api.nvim_buf_get_name(buf)
	local path = e.name == "" and from or resolve(root, e.name, from)
	if not path then
		return nil, "note not found: " .. e.name
	end
	local lines, ver = source(path)
	if not lines and e.name ~= "" then
		-- Moved or deleted since the index was built.
		path = resolve(root, e.name, from, true)
		if path then
			lines, ver = source(path)
		end
	end
	if not lines then
		return nil, "note not found: " .. e.name
	end

	local key = table.concat({ path, ver, e.sub or "", width, tostring(M.config.hide_title) }, "\0")
	if rendered[key] then
		return rendered[key]
	end

	local content = strip_frontmatter(lines)
	if e.sub then
		local is_block = e.sub:sub(1, 1) == "^"
		content = is_block and block(content, e.sub:sub(2)) or section(content, e.sub)
		if not content then
			return nil,
				("%s %q not found in %s"):format(
					is_block and "block" or "heading",
					e.sub,
					e.name ~= "" and e.name or "this note"
				)
		end
	end
	content = clean(content, not e.sub)

	local out, state = {}, {}
	for _, l in ipairs(content) do
		if l == "" then
			table.insert(out, {})
		else
			local segs, hang, kind = format_line(l, state)
			if kind == "rule" then
				table.insert(out, { { string.rep("─", math.min(width, 40)), "NoteEmbedMuted" } })
			else
				vim.list_extend(out, wrap(segs, width, math.min(hang, math.floor(width / 2))))
			end
		end
	end

	if rendered_count > 400 then
		rendered, rendered_count = {}, 0
	end
	rendered[key] = out
	rendered_count = rendered_count + 1
	return out
end

------------------------------------------------------------------- state --

local modes

local function load_modes()
	if modes then
		return modes
	end
	modes = {}
	local ok, data = pcall(vim.fn.readfile, STATE_FILE)
	if ok and data[1] then
		local ok2, t = pcall(vim.json.decode, table.concat(data, "\n"))
		if ok2 and type(t) == "table" then
			modes = t
		end
	end
	return modes
end

local function save_modes()
	pcall(vim.fn.writefile, { vim.json.encode(modes) }, STATE_FILE)
end

--- Every embed on a line: { s, e (1-based byte cols), name, sub, key }.
local function parse(line)
	local out, init = {}, 1
	while true do
		local s, e, inner = line:find("!%[%[([^%]]-)%]%]", init)
		if not s then
			break
		end
		init = e + 1
		local _, ticks = line:sub(1, s - 1):gsub("`", "")
		if ticks % 2 == 0 then -- not inside inline code
			local target = vim.trim(inner:match("^[^|]*"))
			local name, sub = target:match("^([^#]*)#(.*)$")
			name = vim.trim(name or target)
			sub = sub and vim.trim(sub) or ""
			local ext = name:match("%.(%w+)$")
			if not (ext and MEDIA[ext:lower()]) then
				table.insert(out, { s = s, e = e, name = name, sub = sub ~= "" and sub or nil, key = target:lower() })
			end
		end
	end
	return out
end

local function hint()
	return M.config.toggle_key and (M.config.toggle_key .. " cycles") or ":NoteEmbeds cycle"
end

---------------------------------------------------------------- rendering --

local function map_key(buf)
	local key = M.config.toggle_key
	if key and not vim.b[buf].note_embeds_mapped then
		vim.keymap.set("n", key, function()
			M.cycle()
		end, { buffer = buf, desc = "Note embed: preview / full / collapsed" })
		vim.b[buf].note_embeds_mapped = true
	end
end

function M.render(buf)
	buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	if not M.config.enabled or vim.bo[buf].filetype ~= "markdown" then
		return
	end
	local root = vault_root(buf)
	if not root then
		return
	end
	map_key(buf)
	local win = vim.fn.bufwinid(buf)
	if win == -1 then
		return -- drawn on BufWinEnter, when there is a width to wrap to
	end
	local info = vim.fn.getwininfo(win)[1]
	local avail = info.width - info.textoff
	local tabstop = vim.bo[buf].tabstop
	local bar = M.config.bar .. " "
	local state = load_modes()

	local fence = false
	for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if is_fence(line) then
			fence = not fence
		elseif not fence and line:find("![[", 1, true) then
			for _, e in ipairs(parse(line)) do
				-- Line the box up with the embed when only indentation or a list
				-- marker precedes it ("- ![[x]]"), else with the line's indent.
				local before = line:sub(1, e.s - 1):gsub("\t", string.rep(" ", tabstop))
				local indent = (before:match("^%s*[-*+>]?%s*$") or before:match("^%s*%d+[.)]%s*$")) and strwidth(before)
					or #before:match("^%s*")
				local width = avail - indent - strwidth(bar) - 1
				if M.config.max_width then
					width = math.min(width, M.config.max_width)
				end
				width = math.max(width, 20)

				local vl = {}
				local function add(chunks, bar_hl)
					local l = {}
					if indent > 0 then
						l[1] = { string.rep(" ", indent), "NoteEmbedText" }
					end
					l[#l + 1] = { bar, bar_hl or "NoteEmbedBar" }
					vim.list_extend(l, chunks)
					vl[#vl + 1] = l
				end

				local out, err = body(buf, root, e, width)
				local mode = state[e.key] or M.config.default_mode
				if not out then
					add({ { "󰀦 " .. err, "NoteEmbedWarn" } }, "NoteEmbedWarn")
				elseif #out == 0 then
					add({ { e.sub and "(empty section)" or "(empty note)", "NoteEmbedMuted" } })
				elseif mode == "collapsed" then
					add({
						{
							("󰅂 %d line%s hidden · %s"):format(#out, #out == 1 and "" or "s", hint()),
							"NoteEmbedMuted",
						},
					})
				else
					local limit = #out
					-- Hiding a single line saves nothing: the footer takes its place.
					if mode == "preview" and M.config.max_lines > 0 and #out > M.config.max_lines + 1 then
						limit = M.config.max_lines
					end
					for k = 1, limit do
						add(out[k])
					end
					if #out > limit then
						local more = #out - limit
						add({
							{
								("… %d more line%s · %s"):format(more, more == 1 and "" or "s", hint()),
								"NoteEmbedMuted",
							},
						})
					end
				end
				pcall(vim.api.nvim_buf_set_extmark, buf, ns, row - 1, 0, { virt_lines = vl })
			end
		end
	end
end

local pending = {}

local function schedule(buf, delay)
	if pending[buf] then
		return
	end
	pending[buf] = true
	vim.defer_fn(function()
		pending[buf] = nil
		M.render(buf)
	end, delay or 0)
end

local function render_visible(delay)
	local seen = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local b = vim.api.nvim_win_get_buf(win)
		if not seen[b] and vim.bo[b].filetype == "markdown" then
			seen[b] = true
			schedule(b, delay)
		end
	end
end

--- Cycle (or set) the mode of the embed under the cursor.
function M.cycle(to)
	local line = vim.api.nvim_get_current_line()
	local es = parse(line)
	if #es == 0 then
		vim.notify("No note embed on this line", vim.log.levels.INFO)
		return
	end
	local col = vim.fn.col(".")
	local pick = es[1]
	for _, e in ipairs(es) do
		if col >= e.s and col <= e.e then
			pick = e
		end
	end
	local state = load_modes()
	local cur = state[pick.key] or M.config.default_mode
	if not to then
		local order = M.config.max_lines > 0 and MODES or { "full", "collapsed" }
		local i = 0
		for k, m in ipairs(order) do
			if m == cur then
				i = k
			end
		end
		to = order[i % #order + 1]
	end
	state[pick.key] = to ~= M.config.default_mode and to or nil
	save_modes()
	vim.api.nvim_echo({ { ("![[%s]] → %s"):format(pick.key, to) } }, false, {})
	render_visible()
end

-------------------------------------------------------------------- setup --

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
	rendered, rendered_count = {}, 0
	define_hl()

	local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
	local function markdown(buf)
		return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "markdown"
	end

	vim.api.nvim_create_autocmd({ "BufWinEnter", "FileType" }, {
		group = group,
		desc = "Render note embeds",
		callback = function(ev)
			if markdown(ev.buf) then
				schedule(ev.buf)
			end
		end,
	})
	-- Any markdown edit re-renders every visible note, so an embed follows its
	-- source live when both are open side by side.
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
		group = group,
		callback = function(ev)
			if markdown(ev.buf) then
				render_visible(120)
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = "*.md",
		callback = function(ev)
			local path = vim.api.nvim_buf_get_name(ev.buf)
			for root, idx in pairs(indexes) do
				if path:sub(1, #root + 1) == root .. "/" then
					local rel = path:sub(#root + 2)
					local stem = rel:match("([^/]+)%.md$"):lower()
					idx.by_name[stem] = idx.by_name[stem] or {}
					if not vim.tbl_contains(idx.by_name[stem], rel) then
						table.insert(idx.by_name[stem], rel)
					end
				end
			end
			render_visible()
		end,
	})
	-- Agents and Obsidian edit notes outside Neovim; the mtime check in
	-- source() picks those up on the next render.
	vim.api.nvim_create_autocmd({ "FocusGained", "VimResized" }, {
		group = group,
		callback = function()
			render_visible()
		end,
	})
	vim.api.nvim_create_autocmd("WinResized", {
		group = group,
		callback = function()
			for _, win in ipairs(vim.v.event.windows or {}) do
				if vim.api.nvim_win_is_valid(win) then
					local b = vim.api.nvim_win_get_buf(win)
					if markdown(b) then
						schedule(b)
					end
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = define_hl })

	local subs = { "toggle", "on", "off", "cycle", "preview", "full", "collapsed", "refresh" }
	vim.api.nvim_create_user_command("NoteEmbeds", function(o)
		local a = o.args ~= "" and o.args or "toggle"
		if a == "toggle" then
			M.config.enabled = not M.config.enabled
		elseif a == "on" or a == "off" then
			M.config.enabled = a == "on"
		elseif a == "cycle" then
			return M.cycle()
		elseif a == "preview" or a == "full" or a == "collapsed" then
			return M.cycle(a)
		elseif a == "refresh" then
			indexes, files, rendered, rendered_count = {}, {}, {}, 0
		else
			vim.notify("NoteEmbeds: unknown argument " .. a, vim.log.levels.ERROR)
			return
		end
		render_visible()
	end, {
		nargs = "?",
		complete = function()
			return subs
		end,
		desc = "Note embeds: toggle/on/off, cycle/preview/full/collapsed the one under the cursor, refresh",
	})

	render_visible()
end

return M
