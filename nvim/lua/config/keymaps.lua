-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
-- Remap 'H' to '$' in normal mode
-- vim.api.nvim_set_keymap("n", "L", "$", { noremap = true })

-- Remap 'L' to '^' in normal mode
-- vim.api.nvim_set_keymap("n", "H", "^", { noremap = true })
--
-- This is the real file
vim.api.nvim_set_keymap("n", "<C-u>", "<C-u>zz", { noremap = true })
vim.api.nvim_set_keymap("n", "<C-d>", "<C-d>zz", { noremap = true })
vim.api.nvim_set_keymap("i", "<C-BS>", "<C-w>", { noremap = true })
-- select all
vim.api.nvim_set_keymap("n", "<C-a>", "gg<S-v>G", { noremap = true })
vim.api.nvim_set_keymap("n", "N", "Nzzzv", { noremap = true })
vim.api.nvim_set_keymap("n", "n", "nzzzv", { noremap = true })
-- Enter will insetr a line and keep the user in normal mode
vim.api.nvim_set_keymap("n", "<M-o>", "o<Esc>", { noremap = true })
vim.api.nvim_set_keymap("n", "<M-O>", "O<Esc>", { noremap = true })
-- ctrl + backspace is dw
vim.api.nvim_set_keymap("i", "<C-@>", "<C-\\><C-o>db", { noremap = true })
vim.api.nvim_set_keymap("i", "<C-h>", "<Esc><C-h>", { noremap = true })

vim.keymap.set("n", "<leader>r", ":RunCode<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rf", ":RunFile<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rft", ":RunFile tab<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rp", ":RunProject<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rc", ":RunClose<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>crf", ":CRFiletype<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>crp", ":CRProjects<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>ab", ":DapToggleBreakpoint<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ai", ":DapStepInto<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ao", ":DapStepOut<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ax", ":DapTerminate<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>as", ":DapStepOver<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ar", ":DapContinue<CR>", { noremap = true, silent = true })

vim.keymap.set("n", "<leader>m", require("grapple").toggle)
vim.keymap.set("n", "<leader>ha", require("harpoon.mark").add_file, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ht", require("harpoon.ui").toggle_quick_menu, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>hn", require("harpoon.ui").nav_next, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>hp", require("harpoon.ui").nav_prev, { noremap = true, silent = true })
-- vim.keymap.set("n", "<leader>m", require("grapple").toggle)
