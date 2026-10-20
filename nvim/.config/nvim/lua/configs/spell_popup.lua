-- z= — spelling suggestions in a small popup next to the word.
--
-- Built-in z= prints its list as one long message, and noice's
-- long_message_to_split preset turns that into a split buffer at the bottom of
-- the screen. This keeps the same keys (z=, a number, <CR>; q or <Esc>
-- cancels) but shows the list in a float at the word.
--
-- A count (1z=) still runs the built-in, which takes that suggestion directly.

local M = {}

local MAX = 20

-- The misspelled word under or after the cursor (same rule as built-in z=),
-- falling back to the word under the cursor. Returns row, 0-based start byte,
-- the word, and whether it is only a capitalization error.
local function target()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0))
	-- Without an argument spellbadword() moves the cursor to the bad word.
	local bad = vim.fn.spellbadword()
	if bad[1] ~= "" then
		return row, vim.api.nvim_win_get_cursor(0)[2], bad[1], bad[2] == "caps"
	end
	local m = vim.fn.matchstrpos(vim.api.nvim_get_current_line(), [[\k*\%]] .. (col + 1) .. [[c\k\+]])
	if m[1] == "" then
		return nil
	end
	vim.api.nvim_win_set_cursor(0, { row, m[2] })
	return row, m[2], m[1], false
end

function M.suggest()
	if vim.v.count > 0 then
		vim.cmd("normal! " .. vim.v.count .. "z=")
		return
	end

	local row, start, word, caps = target()
	if not word then
		vim.notify("No word under the cursor", vim.log.levels.WARN, { title = "Spelling" })
		return
	end
	local items = vim.fn.spellsuggest(word, MAX, caps)
	if #items == 0 then
		vim.notify("No suggestions for " .. word, vim.log.levels.INFO, { title = "Spelling" })
		return
	end

	local src_win, src_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
	local lines, width = {}, vim.api.nvim_strwidth(word) + 2
	for i, s in ipairs(items) do
		lines[i] = string.format("%2d  %s", i, s)
		width = math.max(width, vim.api.nvim_strwidth(lines[i]) + 1)
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"

	-- Below the word, or above it when the list fits better there.
	local below = vim.api.nvim_win_get_height(0) - vim.fn.winline()
	local above = vim.fn.winline() - 1
	local up = below < #lines + 2 and above > below
	local height = math.max(1, math.min(#lines, (up and above or below) - 2))

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "cursor",
		anchor = up and "SW" or "NW",
		row = up and 0 or 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " " .. word .. " ",
	})
	vim.wo[win].cursorline = true
	vim.fn.matchadd("Number", [[^\s*\d\+]], 10, -1, { window = win })

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function pick()
		local choice = items[vim.api.nvim_win_get_cursor(win)[1]]
		close()
		if vim.api.nvim_win_is_valid(src_win) then
			vim.api.nvim_set_current_win(src_win)
		end
		vim.api.nvim_buf_set_text(src_buf, row - 1, start, row - 1, start + #word, { choice })
		vim.api.nvim_win_set_cursor(src_win, { row, start })
	end

	-- Digits build a number the way the built-in prompt does: 1 then 2 jumps
	-- to 12, <BS> drops the last digit, <CR> takes the highlighted line.
	local typed = 0
	local function jump(n)
		typed = n
		if n >= 1 then
			vim.api.nvim_win_set_cursor(win, { n, 0 })
		end
	end
	local opts = { buffer = buf, nowait = true }
	for d = 0, 9 do
		vim.keymap.set("n", tostring(d), function()
			local n = typed * 10 + d
			if n > #items then
				n = d
			end
			if n <= #items then
				jump(n)
			end
		end, opts)
	end
	vim.keymap.set("n", "<BS>", function()
		jump(math.floor(typed / 10))
	end, opts)
	vim.keymap.set("n", "<CR>", pick, opts)
	vim.keymap.set("n", "<LeftRelease>", pick, opts)
	vim.keymap.set("n", "q", close, opts)
	vim.keymap.set("n", "<Esc>", close, opts)
	vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })
end

return M
