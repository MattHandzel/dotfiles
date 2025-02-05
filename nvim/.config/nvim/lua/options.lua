-- require "nvchad.options"

------------------------------------------------------------------------------------------------------------------------------------------------------
local opt = vim.opt
local o = vim.o
local g = vim.g

-------------------------------------- globals -----------------------------------------
g.toggle_theme_icon = "   "

-------------------------------------- options ------------------------------------------
o.laststatus = 3
o.showmode = false

o.clipboard = "unnamedplus"
o.cursorline = true
o.cursorlineopt = "number"

-- Indenting
o.expandtab = true
o.shiftwidth = 2
o.smartindent = true
o.tabstop = 2
o.softtabstop = 2

opt.fillchars = { eob = " " }
o.ignorecase = true
o.smartcase = true
o.mouse = "a"

-- Numbers
o.number = true
o.numberwidth = 2
o.ruler = false

-- disable nvim intro
opt.shortmess:append("sI")

o.signcolumn = "yes"
o.splitbelow = true
o.splitright = true
o.timeoutlen = 400
o.undofile = true

-- interval for writing swap file to disk, also used by gitsigns
o.updatetime = 250

-- go to previous/next line with h,l,left arrow and right arrow
-- when cursor reaches end/beginning of line
opt.whichwrap:append("<>[]hl")

-- g.mapleader = " "

-- disable some default providers
vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"
vim.g.python3_host_prog = vim.fn.exepath("python3")
vim.g.node_host_prog = "/run/current-system/sw/bin/node"
-- vim.g.loaded_node_provider = 1
vim.g["loaded_node_provider"] = 1
vim.g["loaded_python3_provider"] = 1
-- vim.g["loaded_perl_provider"] = 0
-- vim.g["loaded_ruby_provider"] = 0

-- add binaries installed by mason.nvim to path
local is_windows = vim.loop.os_uname().sysname == "Windows_NT"
vim.env.PATH = vim.fn.stdpath("data") .. "/mason/bin" .. (is_windows and ";" or ":") .. vim.env.PATH

vim.o.relativenumber = true

-------------------------------------------------------------------------------------------------------------------------------------------------

local function customize_colorscheme()
	-- Use Vim script syntax with vim.cmd
	vim.cmd([[
    highlight LineNr ctermfg=White guifg=#e2e2e2
    highlight CursorLineNr ctermfg=Yellow guifg=#e5cfff
highlight Comment ctermfg=Gray guifg=#9898af

    " Add more highlight modifications here
  ]])
end
customize_colorscheme()

vim.wo.spell = true
vim.bo.spelllang = "en_us"
-- Set Vimtex options
vim.g.vimtex_compiler_latexmk = {
	options = {
		"-shell-escape",
		"-verbose",
		"-file-line-error",
		"-synctex=1",
		'-xelatex="xelatex -shell-escape"',
		"-interaction=nonstopmode",
	},
	-- options = {
	--         "-pdflatex=pdflatex -shell-escape",
	--         "-pdf"
	--     }
}
vim.opt_local.conceallevel = 2

vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "nvim_treesitter#foldexpr()"
