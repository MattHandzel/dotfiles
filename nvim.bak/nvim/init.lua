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
function ApplyAllCodeActions()
  local bufnr = vim.api.nvim_get_current_buf()
  vim.lsp.buf_request(bufnr, 'textDocument/codeAction', {
    textDocument = vim.lsp.util.make_text_document_params(),
    range = { start = { line = 0, character = 0 }, ['end'] = { line = vim.fn.line("$"), character = 0 } },
    context = {
      diagnostics = vim.lsp.diagnostic.get_all()[bufnr],
    },
  }, function(err, _, actions)
    if err then
      print('Error when fetching code actions: ' .. err)
    else
      for _, action in pairs(actions or {}) do
        if action.edit or type(action.command) == "table" then
          if action.edit then
            vim.lsp.util.apply_workspace_edit(action.edit)
          end
          if type(action.command) == "table" then
            vim.lsp.buf.execute_command(action.command)
          end
        end
      end
    end
  end)
end
}
