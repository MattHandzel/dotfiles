-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
vim.cmd("colorscheme catppuccin")
local lspconfig = require("lspconfig")
lspconfig.ltex.setup({
  checkfrequency = "save",
})

-- vim.api.nvim_create_autocmd("VimEnter", {
--   pattern = "*",
--
--   callback = function()
--     vim.api.nvim_input("<leader>up")
--   end,
-- })

-- vim.api.nvim_create_autocmd("User", {
--   callback = function()
--     local ok, buf = pcall(vim.api.nvim_win_get_buf, vim.g.coc_last_float_win)
--     if ok then
--       vim.keymap.set("n", "K", function()
--         require("link-visitor").link_under_cursor()
--       end, { buffer = buf })
--       vim.keymap.set("n", "L", function()
--         require("link-visitor").link_near_cursor()
--       end, { buffer = buf })
--     end
--   end,
--   pattern = "CocOpenFloat",
-- })
local function customize_colorscheme()
  -- Use Vim script syntax with vim.cmd
  vim.cmd([[
    highlight LineNr ctermfg=White guifg=#e2e2e2
    highlight CursorLineNr ctermfg=Yellow guifg=#e5cfff
highlight Comment ctermfg=Gray guifg=#9898af

    " Add more highlight modifications here
  ]])
end

-- Function to check for nvim-cmp and setup the keybinding
-- local cmp = require("cmp")
-- if cmp then
--   cmp.setup({
--     mapping = {
--       ["<Left>"] = cmp.mapping.confirm({ select = true }),
--     },
--   })
-- end
customize_colorscheme()
-- require("neodev").setup({
--   library = { plugins = { "neotest" }, types = true },
--   ...,
-- })
-- require("pqf").setup()
-- require("neotest").setup({
--   adapters = {
--     require("neotest-python"),
--     require("neotest-gtest").setup({}),
--   },
-- })

require("lazy").setup({
  { "CRAG666/code_runner.nvim", config = true },
})

-- require("usage-tracker").setup({
--   keep_eventlog_days = 14,
--   cleanup_freq_days = 7,
--   event_wait_period_in_sec = 5,
--   inactivity_threshold_in_min = 5,
--   inactivity_check_freq_in_sec = 5,
--   verbose = 0,
--   telemetry_endpoint = "", -- you'll need to start the restapi for this feature
-- })
local betterTerm = require("betterTerm")

-- toggle firts term
vim.keymap.set({ "n", "t" }, "<C-;>", betterTerm.open, { desc = "Open terminal" })
-- Select term focus
vim.keymap.set({ "n" }, "<leader>tt", betterTerm.select, { desc = "Select terminal" })
-- Create new term
local current = 0
vim.keymap.set({ "n" }, "<leader>tn", function()
  betterTerm.open(current)
  current = current + 1
end, { desc = "New terminal" })
betterTerm.setup()
-- this is a config example
require("betterTerm").setup({
  prefix = "CRAG_",
  startInserted = false,
  position = "bot",
  size = 25,
})
-- use the best keymap for you
-- change 1 for other terminal id
-- Change "get_filetype_command()" to "get_project_command().command" for running projects
require("code_runner").setup({
  filetype_path = vim.fn.expand("~/.config/nvim/code_runner_filetypes.json"),
  project_path = vim.fn.expand("~/.config/nvim/code_runner_projects.json"),
  -- filetype = {
  --   java = {
  --     "cd $dir &&",
  --     "javac $fileName &&",
  --     "java $fileNameWithoutExt",
  --   },
  --   python = "python3 -u",
  --   typescript = "deno run",
  --   rust = {
  --     "cd $dir &&",
  --     "rustc $fileName &&",
  --     "$dir/$fileNameWithoutExt",
  --   },
  -- c = {
  --   "cd $dir &&",
  --   "gcc $fileName",
  --   "-o $fileNameWithoutExt &&",
  --   "$dir/$fileNameWithoutExt",
  -- },
  -- cpp = {
  --   "cd $dir &&",
  --   "g++ $fileName",
  --
  --   "-o $fileNameWithoutExt &&",
  --   "$dir/$fileNameWithoutExt",
  -- },
  -- },

  -- project = {
  -- ["~/python/intel_2021_1"] = {
  --   name = "Intel Course 2021",
  --   description = "Simple python project",
  --   file_name = "POO/main.py",
  -- },
  -- ["~/deno/example"] = {
  --   name = "ExapleDeno",
  --   description = "Project with deno using other command",
  --   file_name = "http/main.ts",
  --   command = "deno run --allow-net",
  -- },
  -- ["~/sp24_cs341_handzel4/extreme_edge_cases"] = {
  --   name = "extreme_edge_cases",
  --   description = "Project with make file",
  --   command = "make debug && ./*debug",
  -- },
  -- ["~/sp24_cs341_handzel4/vector"] = {
  --   name = "extreme_edge_cases",
  --   description = "Project with make file",
  --   command = "gcc vector_test.c -o vector_test && ./vector_test",
  -- },
  -- ["~/UIUC/CS341/sp24_cs341_handzel4/vector"] = {
  --   name = "vector1",
  --   description = "",
  --   command = "make vector_test && ./vector_test",
  -- },
  -- },
  -- project_path = "~/.config/nvim/code_runner_projects.json",
})

-- vim.cmd("highlight! HarpoonInactive guibg=NONE guifg=#63698c")
-- vim.cmd("highlight! HarpoonActive guibg=NONE guifg=white")
-- vim.cmd("highlight! HarpoonNumberActive guibg=NONE guifg=#7aa2f7")
-- vim.cmd("highlight! HarpoonNumberInactive guibg=NONE guifg=#7aa2f7")
-- vim.cmd("highlight! TabLineFill guibg=NONE guifg=white")

-- vim.api.nvim_create_autocmd("BufWritePre", {
--   pattern = "*.tex",
--   command = "silent! execute '!latexindent' shellescape(@%, 1) '>' shellescape(@%, 1)",
-- })
vim.keymap.set("i", "<C-k>", "<Esc>:TmuxNavigateUp<CR>i", { noremap = true, silent = true })
vim.keymap.set("i", "<C-j>", "<Esc>:TmuxNavigateDown<CR>i", { noremap = true, silent = true })
vim.keymap.set("i", "<C-h>", "<Esc>:TmuxNavigateLeft<CR>i", { noremap = true, silent = true })
vim.keymap.set("i", "<C-l>", "<Esc>:TmuxNavigateRight<CR>i", { noremap = true, silent = true })

require("telescope").load_extension("harpoon")

for i = 97, 122 do -- ASCII values for 'a' to 'z'
  local mark = string.char(i)
  vim.api.nvim_set_keymap("n", "dm" .. mark, "<cmd>delmarks " .. mark .. "<CR>", { noremap = true, silent = true })
end

-- anoyying nitification pop us
-- vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
--   -- Disable virtual_text (inline diagnostics)
--   virtual_text = false,
--   -- Keep the signs in the sign column
--   signs = true,
--   -- Disable the pop-up messages
--   update_in_insert = false,
-- })
-- o
-- vim.lsp.lsp_handlers["window/showMessage"] = vim.lsp.with(vim.lsp.handlers["window/showMessage"], { log = false, updates })
--
--

-- Save the original vim.notify function
-- local original_notify = vim.notify

-- Override vim.notify with a custom function
-- vim.notify = function(msg, log_level, opts)
-- Example condition to filter out notifications
-- This example ignores all notifications, but you can add custom logic
-- if log_level == vim.log.levels.INFO then
-- Ignore the notification
-- return
-- end

-- For all other notifications, use the original notify function
-- original_notify(msg, log_level, opts)
-- end
