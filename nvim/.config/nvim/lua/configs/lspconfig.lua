-- Setup language servers.
local lspconfig = require("lspconfig")
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.offsetEncoding = { "utf-16" }

vim.diagnostic.config({
	virtual_text = true,
	signs = true,
	underline = true,
	update_in_insert = false,
	severity_sort = true,
	float = {
		border = "rounded",
		source = "if_many",
	},
})

lspconfig.rust_analyzer.setup({
	-- Server-specific settings. See `:help lspconfig-setup`
	settings = {
		["rust-analyzer"] = {},
	},
})

lspconfig.pyright.setup({})
lspconfig.ts_ls.setup({
	capabilities = capabilities,
	settings = {
		typescript = {
			tsserver = {
				-- Any specific settings you need
			},
		},
	},
})

-- Markdown/prose grammar+spell now runs on harper-ls (Rust, ~20MB RSS, no JVM)
-- instead of ltex-ls. ltex spawned one 512MB+ LanguageTool JVM PER GIT ROOT — the
-- Obsidian vault (a git repo) plus every project repo you edit markdown in — which
-- left ~1.3GB of idle JVMs parked in zram on this 16GB machine. harper's footprint
-- is negligible. Dictionary lives in spell/harper-dict.txt (one word per line).
lspconfig.harper_ls.setup({
	filetypes = { "markdown", "gitcommit" },
	settings = {
		["harper-ls"] = {
			userDictPath = vim.fn.expand("~/dotfiles/nvim/.config/nvim/spell/harper-dict.txt"),
		},
	},
})

-- ltex-ls kept for LaTeX ONLY. tex is rare, so its heavy JVM now spawns rarely
-- instead of once per markdown git root. Markdown moved to harper_ls above.
lspconfig.ltex.setup({
	cmd = {
		"env",
		"JAVA_TOOL_OPTIONS=-Xms128m -Xmx512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -Dorg.bsplines.ltexls.logLevel=WARNING",
		"ltex-ls",
	},
	filetypes = { "tex" },
	flags = { debounce_text_changes = 1000 },
	settings = {
		ltex = {
			checkFrequency = "save",
			dictionary = {
				["en-US"] = {
					"LMNT",
					"malate",
					"Malate",
					"erythritol",
					"BulkSupplements",
					"Zvi",
				},
			},
		},
	},
})
-- lspconfig.rust_analyzer.setup({
-- 	-- Server-specific settings. See `:help lspconfig-setup`
-- 	settings = {
-- 		["rust-analyzer"] = {},
-- 	},
-- })
lspconfig.hls.setup({
	filetypes = { "haskell", "lhaskell", "cabal" },
})

lspconfig.nixd.setup({})

lspconfig.clangd.setup({ capabilities = capabilities })
lspconfig.denols.setup({})

-- go setup
lspconfig.gopls.setup({
	cmd = { "gopls", "serve" },
	capabilities = capabilities,
	settings = {
		gopls = {
			analyses = {
				unusedparams = true,
			},
			staticcheck = true,
		},
	},
})

-- Global mappings.
-- See `:help vim.diagnostic.*` for documentation on any of the below functions
vim.keymap.set("n", "<space>e", vim.diagnostic.open_float)
vim.keymap.set("n", "[d", vim.diagnostic.goto_prev)
vim.keymap.set("n", "]d", vim.diagnostic.goto_next)
vim.keymap.set("n", "<space>q", vim.diagnostic.setloclist)

-- Use LspAttach autocommand to only map the following keys
-- after the language server attaches to the current buffer
vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = function(ev)
		-- Enable completion triggered by <c-x><c-o>
		vim.bo[ev.buf].omnifunc = "v:lua.vim.lsp.omnifunc"

		-- Buffer local mappings.
		-- See `:help vim.lsp.*` for documentation on any of the below functions
		local opts = { buffer = ev.buf }
		local run_zz_after_running_the_argument = function(arg)
			return function()
				arg()
				vim.cmd("normal! zz")
			end
		end
		vim.keymap.set("n", "gD", run_zz_after_running_the_argument(vim.lsp.buf.declaration), opts)

		vim.keymap.set("n", "gd", run_zz_after_running_the_argument(vim.lsp.buf.definition), opts)
		vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
		vim.keymap.set("n", "gi", run_zz_after_running_the_argument(vim.lsp.buf.implementation), opts)
		vim.keymap.set("n", "<M-K>", vim.lsp.buf.signature_help, opts)
		vim.keymap.set("n", "<leader>wa", vim.lsp.buf.add_workspace_folder, opts)
		vim.keymap.set("n", "<leader>wr", vim.lsp.buf.remove_workspace_folder, opts)
		vim.keymap.set("n", "<leader>wl", function()
			print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
		end, opts)
		vim.keymap.set("n", "<leader>D", run_zz_after_running_the_argument(vim.lsp.buf.type_definition), opts)
		vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, opts)
		vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
		vim.keymap.set("n", "gr", run_zz_after_running_the_argument(vim.lsp.buf.references), opts)
		vim.keymap.set("n", "<leader>f", function()
			vim.lsp.buf.format({ async = true })
		end, opts)
	end,
})
