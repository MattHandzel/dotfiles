-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
--
-- Remap 'H' to '$' in normal mode
-- vim.api.nvim_set_keymap("n", "L", "$", { noremap = true })

-- Remap 'L' to '^' in normal mode
-- vim.api.nvim_set_keymap("n", "H", "^", { noremap = true })
--
vim.api.nvim_set_keymap("n", "<C-u>", "<C-u>zz", { noremap = true })
vim.api.nvim_set_keymap("n", "<C-d>", "<C-d>zz", { noremap = true })
vim.api.nvim_set_keymap("i", "<C-BS>", "<C-w>", { noremap = true })
-- select all
vim.api.nvim_set_keymap("n", "<C-a>", "gg<S-v>G", { noremap = true })
vim.api.nvim_set_keymap("n", "N", "Nzzzv", { noremap = true })
vim.api.nvim_set_keymap("n", "n", "nzzzv", { noremap = true })

vim.api.nvim_set_keymap("n", "d~", "<C-a>d", { noremap = true })
-- Enter will insetr a line and keep the user in normal mode
vim.api.nvim_set_keymap("n", "<CR>", "o<Esc>", { noremap = true })
vim.api.nvim_set_keymap("n", "<S-Enter>", "O<Esc>", { noremap = true })

-- ctrl + backspace is dw
-- vim.api.nvim_set_keymap("i", "<C-@>", "<C-\\><C-o>db", { noremap = true })
vim.keymap.set("n", "<leader>r", ":RunCode<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rf", ":RunFile<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rft", ":RunFile tab<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rp", ":RunProject<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rc", ":RunClose<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>crf", ":CRFiletype<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>crp", ":CRProjects<CR>", { noremap = true, silent = false })
