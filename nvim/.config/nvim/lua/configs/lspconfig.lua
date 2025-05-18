-- Setup language servers.
local lspconfig = require("lspconfig")
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.offsetEncoding = { "utf-16" }
lspconfig.rust_analyzer.setup({
	-- Server-specific settings. See `:help lspconfig-setup`
	settings = {
		["rust-analyzer"] = {},
	},
})
lspconfig.buf.setup({})
lspconfig.pyright.setup({})
lspconfig.ts_ls.setup({
	on_attach = function(client, bufnr)
		vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
			virtual_text = true,
			signs = true,
			underline = true,
		})
	end,
	-- on_attach = ,
	-- capabilities = capabilities,
	settings = {
		typescript = {
			tsserver = {
				-- Any specific settings you need
			},
		},
	},
})
lspconfig.ltex.setup({
	checkfrequency = "save",
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
	on_attach = function(client, bufnr)
		vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(vim.lsp.diagnostic.on_publish_diagnostics, {
			virtual_text = true,
			signs = true,
			underline = true,
		})
	end,
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
