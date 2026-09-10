local iron = require("iron.core")
local common = require("iron.fts.common")

iron.setup({
	config = {
		-- Whether a terminal should remain open after the process has exited
		should_detach = true,
		-- Can be "vertical", "horizontal", "tab", "floating" or "window"
		scratch_repl = false,
		repl_definition = {
			python = {
				-- Can be a table or a function that returns a table (useful for environments)
				command = { "ipython", "--no-autoindent" },
				format = common.bracketed_paste_python,
			},
		},
		-- How the repl window will be displayed
		-- See below for more options
		repl_open_cmd = require("iron.view").bottom(15),
	},
	-- Iron doesn't set keymaps by default anymore.
	-- You can set them here or elsewhere.
	keymaps = {
		send_motion = "<leader>ic",
		visual_send = "<leader>ic",
		send_file = "<leader>if",
		send_line = "<leader>il",
		send_until_cursor = "<leader>iu",
		send_mark = "<leader>im",
		mark_motion = "<leader>mc",
		mark_visual = "<leader>mc",
		remove_mark = "<leader>md",
		cr = "<leader>i<cr>",
		interrupt = "<leader>i<space>",
		exit = "<leader>iq",
		clear = "<leader>cl",
	},
	-- If the highlight is on, you can change how it looks
	-- For the available options, check nvim_set_hl
	highlight = {
		italic = true,
	},
	ignore_blank_lines = true, -- ignore blank lines when sending visual select lines
})

-- Iron doesn't have a "send cell" by default, but we can make one!
-- This searches for # %% or the beginning of the file, then to the next # %% or end of file.
local function send_cell()
	local iron_core = require("iron.core")
	local current_line = vim.fn.line(".")
	local start_line = vim.fn.search("^# %%", "bnW")
	if start_line == 0 then
		start_line = 1
	end

	local end_line = vim.fn.search("^# %%", "nW", current_line + 1)
	if end_line == 0 then
		end_line = vim.fn.line("$")
	else
		end_line = end_line - 1
	end

	iron_core.send(nil, vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false))
end

vim.keymap.set("n", "<leader>ix", send_cell, { desc = "Iron: Send # %% cell" })
