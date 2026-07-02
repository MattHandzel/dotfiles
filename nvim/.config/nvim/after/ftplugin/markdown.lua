-- Markdown indent: make `>`/`<` shift by 2 spaces (not 4).
-- after/ftplugin loads last, so this overrides any plugin/runtime ftplugin
-- that bumps shiftwidth to 4 for markdown buffers.
vim.bo.expandtab = true
vim.bo.shiftwidth = 2
vim.bo.tabstop = 2
vim.bo.softtabstop = 2
