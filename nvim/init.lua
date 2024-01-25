-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
vim.cmd("colorscheme tokyonight-night")

local function customize_colorscheme()
  -- Use Vim script syntax with vim.cmd
  vim.cmd([[
    highlight LineNr ctermfg=White guifg=#d0d0d0
    highlight CursorLineNr ctermfg=Yellow guifg=#d5b6ff
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
require("pqf").setup()
require("neotest").setup({
  adapters = {
    require("neotest-python"),
    require("neotest-gtest"),
  },
})
require("lazy").setup({
  { "CRAG666/code_runner.nvim", config = true },
})
require("usage-tracker").setup({
  keep_eventlog_days = 14,
  cleanup_freq_days = 7,
  event_wait_period_in_sec = 5,
  inactivity_threshold_in_min = 5,
  inactivity_check_freq_in_sec = 5,
  verbose = 0,
  telemetry_endpoint = "", -- you'll need to start the restapi for this feature
})
local betterTerm = require("betterTerm")

-- toggle firts term
vim.keymap.set({ "n", "t" }, "<C-;>", betterTerm.open, { desc = "Open terminal" })
-- Select term focus
vim.keymap.set({ "n" }, "<leader>tt", betterTerm.select, { desc = "Select terminal" })
-- Create new term
local current = 2
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
vim.keymap.set("n", "<leader>re", function()
  require("betterTerm").send(
    require("code_runner.commands").get_filetype_command(),
    1,
    { clean = false, interrupt = true }
  )
end, { desc = "Excute File" })
require("code_runner").setup({
  filetype = {
    java = {
      "cd $dir &&",
      "javac $fileName &&",
      "java $fileNameWithoutExt",
    },
    python = "python3 -u",
    typescript = "deno run",
    rust = {
      "cd $dir &&",
      "rustc $fileName &&",
      "$dir/$fileNameWithoutExt",
    },
  },
})
