-- Setup language servers.
--
-- The `require("lspconfig")` framework (lspconfig.<server>.setup{}) is
-- deprecated and is removed in nvim-lspconfig v3.0.0; it warned on every
-- start. The replacement is Neovim's own vim.lsp.config()/vim.lsp.enable().
-- nvim-lspconfig still ships each server's cmd/filetypes/root_markers as
-- lsp/<server>.lua, and vim.lsp.config() merges the table below over those
-- defaults, so only the overrides need to live here. See :help lspconfig-nvim-0.11.
--
-- NvChad's require("nvchad.configs.lspconfig").defaults() runs first and
-- already applies capabilities + on_init globally via vim.lsp.config("*", ...).
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

vim.lsp.config("rust_analyzer", {
	-- Server-specific settings. See `:help lspconfig-setup`
	settings = {
		["rust-analyzer"] = {},
	},
})

vim.lsp.config("pyright", {})
vim.lsp.config("ts_ls", {
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
--
-- FOOTGUN (fixed 2026-09-16): harper keys the user dictionary case-insensitively
-- and the LAST matching line wins, so listing both `bluedot` and `Bluedot` left only
-- the capitalized form usable and flagged every lowercase use as a misspelling —
-- silently, with no error anywhere. A lowercase entry already matches every
-- capitalization (`dnd` covers `DnD` and `DND`), so keep ONE lowercase entry per
-- word and never add a capitalized variant of a word already present. The
-- `HarperAddToUserDict` code action appends the word exactly as typed, so it can
-- reintroduce a duplicate; check with:
--   awk '{print tolower($0)}' spell/harper-dict.txt | sort | uniq -d
-- Affix flags (`CAIS/M`) are NOT supported here and break the entry; possessives
-- must be listed in full (`CAIS's`).
vim.lsp.config("harper_ls", {
	filetypes = { "markdown", "gitcommit" },
	settings = {
		["harper-ls"] = {
			userDictPath = vim.fn.expand("~/dotfiles/nvim/.config/nvim/spell/harper-dict.txt"),
			-- The vault is fast, informal, first-person writing; Harper's default
			-- rule set is tuned for polished prose and buried every real typo
			-- under thousands of style hints. Everything below is style/typography
			-- pedantry, not correctness — SpellCheck, RepeatedWords, AnA, MissingTo
			-- etc. stay on. A rule's name is the diagnostic's `code` field (shown
			-- in virtual text / :lua vim.diagnostic.open_float()); to silence a
			-- new one, add it here.
			linters = {
				SentenceCapitalization = false,
				CapitalizePersonalPronouns = false,
				UseTitleCase = false,
				LongSentences = false,
				OxfordComma = false,
				Dashes = false,
				NumericRangeEnDash = false,
				UseEllipsisCharacter = false,
				AvoidCurses = false,
				UnclosedQuotes = false,
				MultipleSequentialPronouns = false,
				-- word-choice nits
				Excellent = false,
				ExpandMinimum = false,
				ExpandTimeShorthands = false,
				OrthographicConsistency = false,
				AvoidAndAlso = false,
				SomewhatSomething = false,
				-- constantly wrong on tech vocab (lifelog, waybar, writeup, ...)
				CompoundNouns = false,
				SplitWords = false,
				DisjointPrefixes = false,
				PhrasalVerbAsCompoundNoun = false,
			},
		},
	},
})

-- ltex-ls kept for LaTeX ONLY. tex is rare, so its heavy JVM now spawns rarely
-- instead of once per markdown git root. Markdown moved to harper_ls above.
vim.lsp.config("ltex", {
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
vim.lsp.config("hls", {
	filetypes = { "haskell", "lhaskell", "cabal" },
})

vim.lsp.config("nixd", {})

vim.lsp.config("clangd", { capabilities = capabilities })
vim.lsp.config("denols", {})

-- go setup
vim.lsp.config("gopls", {
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

-- vim.lsp.config() only registers a config; vim.lsp.enable() is what
-- makes Neovim actually launch the server for matching buffers.
-- (lua_ls is enabled by NvChad's defaults(), so it is not repeated here.)
vim.lsp.enable({
	"rust_analyzer",
	"pyright",
	"ts_ls",
	"harper_ls",
	"ltex",
	"hls",
	"nixd",
	"clangd",
	"denols",
	"gopls",
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

		-- Map K/<M-K> ONLY when the attaching client actually implements the
		-- method. Both clients that attach to a markdown buffer -- copilot and
		-- harper-ls -- attach without implementing textDocument/hover, so an
		-- unconditional map turned every K in a note into
		--   "method textDocument/hover is not supported by any of the servers
		--    registered for the current buffer"
		-- Leaving it unmapped falls back to Vim's builtin K (keywordprg), which
		-- is the more useful behaviour in prose anyway.
		local client = vim.lsp.get_client_by_id(ev.data.client_id)
		if client and client:supports_method("textDocument/hover") then
			-- focusable = false used to be applied globally in options.lua via the
			-- deprecated vim.lsp.with(); it is a plain hover option now.
			vim.keymap.set("n", "K", function()
				vim.lsp.buf.hover({ focusable = false })
			end, opts)
		end
		if client and client:supports_method("textDocument/signatureHelp") then
			vim.keymap.set("n", "<M-K>", vim.lsp.buf.signature_help, opts)
		end

		vim.keymap.set("n", "gi", run_zz_after_running_the_argument(vim.lsp.buf.implementation), opts)
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
