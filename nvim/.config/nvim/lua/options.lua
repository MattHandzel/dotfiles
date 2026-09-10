-- require "nvchad.options"
-- Set the path to Mason's rust-analyzer binary
-- local mason_registry = require("mason-registry")
-- local rust_analyzer_path = mason_registry.get_package("rust-analyzer"):get_install_path() .. "/rust-analyzer"
--
-- -- Configure rustaceanvim
vim.g.rustaceanvim = {
	server = {
		settings = {
			["rust-analyzer"] = {
				-- Add your rust-analyzer settings here
				checkOnSave = {
					command = "clippy",
				},
			},
			diagnostics = {
				enable = true,
				experimental = {
					enable = true,
				},
			},
		},
		on_attach = function(client, bufnr)
			-- Enable nvim-cmp for this buffer
			local cmp = require("cmp")
			cmp.setup.buffer({
				sources = {
					{ name = "nvim_lsp" },
				},
			})
		end,
	},
}

------------------------------------------------------------------------------------------------------------------------------------------------------
local opt = vim.opt
local o = vim.o
local g = vim.g

-------------------------------------- globals -----------------------------------------
g.toggle_theme_icon = "   "
opt.ruler = false

-------------------------------------- options ------------------------------------------
o.laststatus = 3
o.showmode = false

o.clipboard = "unnamedplus"

-- Over SSH, route the system clipboard (+/*) to the LOCAL machine via OSC 52.
-- Locally (no SSH), wl-copy already handles unnamedplus, so leave it alone.
-- (MAT-132: shared clipboard server -> laptop)
if vim.env.SSH_CONNECTION ~= nil then
	vim.g.clipboard = {
		name = "OSC 52",
		copy = {
			["+"] = require("vim.ui.clipboard.osc52").copy("+"),
			["*"] = require("vim.ui.clipboard.osc52").copy("*"),
		},
		paste = {
			["+"] = require("vim.ui.clipboard.osc52").paste("+"),
			["*"] = require("vim.ui.clipboard.osc52").paste("*"),
		},
	}
end
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

--  vim.g.rustaceanvim = {
--    server = {
--      cmd = function()
-- local mason_registry = require('mason-registry')
-- if mason_registry.is_installed('rust-analyzer') then
--   -- This may need to be tweaked depending on the operating system.
--   local ra = mason_registry.get_package('rust-analyzer')
--   local ra_filename = ra:get_receipt():get().links.bin['rust-analyzer']
--   return { ('%s/%s'):format(ra:get_install_path(), ra_filename or 'rust-analyzer') }
-- else
--   -- global installation
--   return { 'rust-analyzer' }
-- end
--      end,
--    },
--  }

-- go to previous/next line with h,l,left arrow and right arrow
-- when cursor reaches end/beginning of line
opt.whichwrap:append("<>[]hl")
vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { focusable = false })
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

-- REMOVED: a customize_colorscheme() that set
--   LineNr #e2e2e2 · CursorLineNr #e5cfff · Comment #9898af
--
-- It never actually applied. options.lua is required early, and base46 loads its
-- cached highlights afterwards (nvim.lua), overwriting all three — at startup
-- those groups measure #45475b / #b4beff / #9399b3, i.e. purely the theme.
--
-- The catch was :ReloadConfig, which re-requires this module *after* base46 has
-- loaded. Then the override won and line numbers turned from grey to white
-- mid-session, with nothing in the config having changed. Deleting it is a no-op
-- at startup and makes a reload look identical to a fresh launch.
--
-- To genuinely override theme colours, do it on the ColorScheme event so it
-- re-applies every time base46 reloads, rather than racing it once:
--   vim.api.nvim_create_autocmd("ColorScheme", { callback = function() ... end })

vim.opt.spell = true
vim.opt.spelllang = "en_us,pl"
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

-- Neovim never rotates or truncates lsp.log. The Codeium (neocodeium) language
-- server logged an ERROR ("[streamChoices] Request id invalid") on essentially
-- every completion request while unauthenticated — that alone grew
-- ~/.local/state/nvim/lsp.log to 1.2GB (99.6% of lines). neocodeium is now
-- disabled (see plugins/quality.lua), but keep this guard regardless.
-- Silence the log; raise to "WARN"/"DEBUG" temporarily when debugging a server.
-- This lives in options.lua, not configs/lspconfig.lua, because the latter is
-- lazy-loaded on LSP attach — too late, and skipped entirely in headless runs.
vim.lsp.set_log_level("OFF")

-- Belt and braces: if the level is ever raised and forgotten, drop the log at
-- startup once it passes 50MB so it can never silently reach GB scale again.
local ok, logpath = pcall(vim.lsp.get_log_path)
if ok and logpath then
	local stat = vim.uv.fs_stat(logpath)
	if stat and stat.size > 50 * 1024 * 1024 then
		local fd = vim.uv.fs_open(logpath, "w", 420) -- truncate, 0644
		if fd then
			vim.uv.fs_close(fd)
		end
	end
end
