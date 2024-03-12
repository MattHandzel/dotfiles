-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
-- Add any additional autocmds here
vim.api.nvim_create_autocmd("BufReadPre", {
  pattern = { "*.pdf" },
  callback = function()
    -- Command to open the file in Zathura
    vim.cmd("!zathura " .. vim.fn.expand("%:p") .. " &")
    -- Close the buffer without saving
    vim.cmd("bd")
  end,
})
