
vim.api.nvim_create_autocmd("BufReadPre", {
  pattern = { "*.pdf" },
  callback = function()
    -- Command to open the file in Zathura
    vim.cmd("!zathura " .. vim.fn.expand("%:p") .. " &")
    -- Close the buffer without saving
    vim.cmd("bd")
  end,
})


