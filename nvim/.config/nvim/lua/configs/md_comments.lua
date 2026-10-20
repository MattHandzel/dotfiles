-- Hide HTML comments (<!-- ... -->) in markdown buffers.
--
-- A comment stays hidden in every mode and only shows when you are in insert
-- or visual mode AND the cursor (or the visual selection) is on it. Normal
-- mode never shows it, not even on the cursor line.
--
-- Why not render-markdown's own `html.comment.conceal`:
--   * it never fired -- Neovim 0.12's bundled markdown injections.scm has no
--     html_block -> html injection (that lived in nvim-treesitter's queries),
--     so render-markdown never saw a single comment node;
--   * even with the injection, its anti-conceal reveals the comment on the
--     cursor line in normal mode, and it stops rendering altogether in insert
--     and visual mode, which would show every comment at once.
--
-- Hiding is done with overlay virtual text (one blank per character, so the
-- wrapped rows of a long comment are covered too), not `conceal`: conceal is always revealed on the cursor line
-- while 'concealcursor' is empty, and render-markdown keeps it empty. The
-- cost is that an inline comment in the middle of a sentence leaves a gap
-- rather than collapsing; full-line comments look like blank lines.

local M = {}

local ns = vim.api.nvim_create_namespace("md_comment_hide")
local AUGROUP = "MarkdownCommentHide"

-- bufnr -> { tick = changedtick, ranges = { {sr, sc, er, ec}, ... } }
local cache = {}

local REVEAL_MODES = { i = true, v = true, V = true, ["\22"] = true }

local QUERIES = {
	markdown = "(html_block) @c",
	markdown_inline = "(html_tag) @c",
}

--- 0-based, end-exclusive ranges of every <!-- --> in the buffer.
local function find_comments(buf)
	local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
	if not ok or not parser then
		return {}
	end
	parser:parse(true)

	local ranges = {}
	local stale = false
	parser:for_each_tree(function(tree, ltree)
		local lang = ltree:lang()
		local src = QUERIES[lang]
		if not src then
			return
		end
		local qok, query = pcall(vim.treesitter.query.parse, lang, src)
		if not qok then
			return
		end
		for _, node in query:iter_captures(tree:root(), buf, 0, -1) do
			-- The tree can lag the buffer (FileType fires while a file is
			-- being (re)loaded), so a node can end past the last line and
			-- get_node_text raised "Index out of bounds" inside the autocmd.
			-- Skip such nodes and leave the result uncached.
			local tok, text = pcall(vim.treesitter.get_node_text, node, buf)
			if not tok then
				stale = true
			elseif text:match("^%s*<!%-%-") then
				local sr, sc, er, ec = node:range()
				-- html_block ends at column 0 of the line after the comment.
				if ec == 0 and er > sr then
					er = er - 1
					ec = #(vim.api.nvim_buf_get_lines(buf, er, er + 1, false)[1] or "")
				end
				table.insert(ranges, { sr, sc, er, ec })
			end
		end
	end)
	return ranges, stale
end

local function comments(buf)
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local entry = cache[buf]
	if not entry or entry.tick ~= tick then
		local ranges, stale = find_comments(buf)
		entry = { tick = stale and -1 or tick, ranges = ranges }
		cache[buf] = entry
	end
	return entry.ranges
end

--- Rows (0-based, inclusive) where comments should be shown, or nil.
local function reveal_rows(buf)
	if vim.api.nvim_get_current_buf() ~= buf then
		return nil
	end
	local mode = vim.api.nvim_get_mode().mode
	if not REVEAL_MODES[mode] then
		return nil
	end
	local cur = vim.fn.line(".") - 1
	if mode == "i" then
		return cur, cur
	end
	local other = vim.fn.line("v") - 1
	return math.min(cur, other), math.max(cur, other)
end

--- Cover bytes [from, to) of `line` with blanks, one overlay per character.
--- An overlay only draws on the screen row where it starts and is cut off at
--- the window edge, so one overlay for a whole comment left every wrapped
--- continuation row visible. One per character puts each blank on whatever
--- row that character wrapped to. Plain spaces are skipped: already blank.
local function blank(buf, row, line, from, to)
	local vcol = vim.fn.strdisplaywidth(line:sub(1, from))
	local col = from
	while col < to do
		local len = vim.str_utf_end(line, col + 1) + 1
		local ch = line:sub(col + 1, col + len)
		local width = ch == "\t" and vim.fn.strdisplaywidth(ch, vcol) or vim.api.nvim_strwidth(ch)
		if ch ~= " " and width > 0 then
			pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, col, {
				virt_text = { { string.rep(" ", width), "" } },
				virt_text_pos = "overlay",
				hl_mode = "combine",
			})
		end
		vcol = vcol + width
		col = col + len
	end
end

function M.render(buf)
	if not buf or buf == 0 then
		buf = vim.api.nvim_get_current_buf()
	end
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	if vim.bo[buf].filetype ~= "markdown" then
		return
	end

	local top, bottom = reveal_rows(buf)
	for _, r in ipairs(comments(buf)) do
		local sr, sc, er, ec = r[1], r[2], r[3], r[4]
		local revealed = top and not (er < top or sr > bottom)
		if not revealed then
			local lines = vim.api.nvim_buf_get_lines(buf, sr, er + 1, false)
			for i, line in ipairs(lines) do
				local row = sr + i - 1
				local from = row == sr and sc or 0
				local to = row == er and ec or #line
				blank(buf, row, line, from, to)
			end
		end
	end
end

local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })

vim.api.nvim_create_autocmd(
	{ "BufWinEnter", "FileType", "TextChanged", "TextChangedI", "CursorMoved", "CursorMovedI", "ModeChanged" },
	{
		group = group,
		desc = "Hide markdown HTML comments except under the cursor in insert/visual",
		callback = function(ev)
			if vim.bo[ev.buf].filetype == "markdown" then
				M.render(ev.buf)
			end
		end,
	}
)

vim.api.nvim_create_autocmd("BufWipeout", {
	group = group,
	callback = function(ev)
		cache[ev.buf] = nil
	end,
})

return M
