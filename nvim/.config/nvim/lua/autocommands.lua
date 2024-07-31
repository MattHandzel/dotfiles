
vim.api.nvim_create_autocmd("BufEnter", {
  pattern = { "*.pdf" },
  callback = function()
    -- Command to open the file in Zathura
        vim.cmd("!zathura " .. vim.fn.expand("%:p") .. " &")
        -- vim.cmd("<C-o>")
        -- vim.cmd("bd!")  -- Close the buffer after confirmation
        -- vim.cmd("
  end,
})



vim.api.nvim_create_autocmd("BufEnter", {
  pattern = { "*.png", "*.jpg", "*.jpeg", "*.gif" },
  callback = function()
    -- Command to open the file in Zathura
    vim.cmd("!feh " .. vim.fn.expand("%:p") .. " &")
  end,
})


-- -- add yours here!
-- vim.api.nvim_create_autocmd("BufWritePre", {
-- 	pattern = "*",
-- 	callback = function(args)
-- 		require("conform").format({ bufnr = args.buf })
-- 	end,
-- })

