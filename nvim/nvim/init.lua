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

-- Set Vimtex options
vim.g.vimtex_compiler_latexmk = {
  ["options"] = {
    "-shell-escape",
    "-verbose",
    "-file-line-error",
    "-synctex=1",
    "-interaction=nonstopmode",
  },
}
