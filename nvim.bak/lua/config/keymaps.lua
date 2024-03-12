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
vim.api.nvim_set_keymap("n", "<leader>gD", "<leader>gDzt", { noremap = true })
vim.api.nvim_set_keymap("n", "<leader>gd", "<leader>gdzt", { noremap = true })
vim.api.nvim_set_keymap("n", "<leader>gI", "<leader>gIdzt", { noremap = true })

vim.keymap.set("n", "<leader>r", ":RunCode<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rf", ":RunFile<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rft", ":RunFile tab<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rp", ":RunProject<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rc", ":RunClose<CR>", { noremap = true, silent = false })

vim.keymap.set("n", "<leader>rrf", ":CRFiletype<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rrp", ":CRProjects<CR>", { noremap = true, silent = false })

vim.keymap.set("n", "<leader>ab", ":DapToggleBreakpoint<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ai", ":DapStepInto<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ao", ":DapStepOut<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ax", ":DapTerminate<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>as", ":DapStepOver<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ar", ":DapContinue<CR>", { noremap = true, silent = true })

-- vim.keymap.set("n", "<leader>m", require("grapple").toggle)
vim.keymap.set("n", "<leader>ha", require("harpoon.mark").add_file, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ht", require("harpoon.ui").toggle_quick_menu, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>hn", require("harpoon.ui").nav_next, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>hp", require("harpoon.ui").nav_prev, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>h1", '<cmd>lua require("harpoon.ui").nav_file(1)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>h2", '<cmd>lua require("harpoon.ui").nav_file(2)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>h3", '<cmd>lua require("harpoon.ui").nav_file(3)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>h4", '<cmd>lua require("harpoon.ui").nav_file(4)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>h5", '<cmd>lua require("harpoon.ui").nav_file(5)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>h6", '<cmd>lua require("harpoon.ui").nav_file(6)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>h7", '<cmd>lua require("harpoon.ui").nav_file(7)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>h8", '<cmd>lua require("harpoon.ui").nav_file(8)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<leader>h9", '<cmd>lua require("harpoon.ui").nav_file(9)<CR>', { noremap = true, silent = true })
-- vim.keymap.set("n", "<leader>m", require("grapple").toggle)
vim.keymap.set("n", "<leader>+n", function()
  require("dial.map").manipulate("increment", "normal")
end)
vim.keymap.set("n", "<leader>+g", function()
  require("dial.map").manipulate("increment", "gnormal")
end)
vim.keymap.set("v", "<leader>+n", function()
  require("dial.map").manipulate("increment", "visual")
end)
vim.keymap.set("v", "<leader>+g", function()
  require("dial.map").manipulate("increment", "gvisual")
end)

vim.keymap.set("n", "<leader>-n", function()
  require("dial.map").manipulate("decrement", "normal")
end)
vim.keymap.set("n", "<leader>-g", function()
  require("dial.map").manipulate("decrement", "gnormal")
end)
vim.keymap.set("v", "<leader>-n", function()
  require("dial.map").manipulate("decrement", "visual")
end)
vim.keymap.set("v", "<leader>-g", function()
  require("dial.map").manipulate("decrement", "gvisual")
end)
vim.keymap.set("n", "<leader>_", ":split<CR>", { noremap = true, silent = true })

-- noetest
-- require("neotest").run.run()
-- require("neotest").run.run(vim.fn.expand("%"))
-- require("neotest").run.run({strategy = "dap"})
-- require("neotest").run.stop()
-- require("neotest").run.attach()
vim.keymap.set("n", "<leader>tr", "<cmd> lua require('neotest').run.run()<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>tf", "<cmd> lua require('neotest').run.run(vim.fn.expand('%'))<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>td", "<cmd> lua require('neotest').run.run({strategy = 'dap'})<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>tx", "<cmd> lua require('neotest').run.stop()<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ta", "<cmd> lua require('neotest').run.attach()<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>tl", "<cmd> lua require('neotest').run.last()<CR>", { noremap = true, silent = true })
-- status window

vim.keymap.set("n", "<leader>ts", "<cmd> lua require('neotest').status.open()<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>tS", "<cmd> lua require('neotest').summary.open()<CR>", { noremap = true, silent = true })

vim.keymap.set("n", "<leader>re", function()
  require("betterTerm").send(require("code_runner.commands").get_filetype_command(), 1, { clean = false, interrupt = true })
end, { desc = "Excute File" })
