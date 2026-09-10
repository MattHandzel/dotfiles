local M = {}

function M.init()
	-- Molten reads these globals before plugin load.
	vim.g.molten_image_provider = "image.nvim"
	vim.g.molten_output_win_max_height = 20
	vim.g.molten_auto_open_output = false
	vim.g.molten_wrap_output = true
	vim.g.molten_virt_text_output = true
	vim.g.molten_virt_lines_off_by_1 = true
end

function M.setup()
	vim.keymap.set("n", "<leader>mi", "<cmd>MoltenInit<CR>", { silent = true, desc = "Molten: Init Jupyter kernel" })
	vim.keymap.set("n", "<leader>me", "<cmd>MoltenEvaluateOperator<CR>", { silent = true, desc = "Molten: Eval operator" })
	vim.keymap.set("n", "<leader>rl", "<cmd>MoltenEvaluateLine<CR>", { silent = true, desc = "Molten: Eval line" })
	vim.keymap.set(
		"v",
		"<leader>rv",
		":<C-u>MoltenEvaluateVisual<CR>gv",
		{ silent = true, desc = "Molten: Eval selection" }
	)
	vim.keymap.set("n", "<leader>rd", "<cmd>MoltenDelete<CR>", { silent = true, desc = "Molten: Delete cell" })
	vim.keymap.set("n", "<leader>oh", "<cmd>MoltenHideOutput<CR>", { silent = true, desc = "Molten: Hide output" })
	vim.keymap.set(
		"n",
		"<leader>os",
		"<cmd>noautocmd MoltenEnterOutput<CR>",
		{ silent = true, desc = "Molten: Show/enter output" }
	)
end

return M
