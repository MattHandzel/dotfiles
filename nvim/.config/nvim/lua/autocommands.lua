
vim.api.nvim_create_autocmd("BufReadPre", {
  pattern = { "*.pdf" },
  callback = function()
    -- Command to open the file in Zathura
    vim.cmd("!zathura " .. vim.fn.expand("%:p") .. " &")
  end,
})


vim.api.nvim_create_autocmd("BufReadPre", {
  pattern = { "*.png", "*.jpg", "*.jpeg", "*.gif" },
  callback = function()
    -- Command to open the file in Zathura
    vim.cmd("!feh " .. vim.fn.expand("%:p") .. " &")
  end,
})
