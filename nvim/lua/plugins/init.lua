return {
	{
		"stevearc/conform.nvim",
		config = function()
			require("configs.conform")
		end,
	},
	{
		"chrisgrieser/cmp_yanky",
		opts = {
			name = "cmp_yanky",
			option = {
				-- only suggest items which match the current filetype
				onlyCurrentFiletype = false,
				-- only suggest items with a minimum length
				minLength = 3,
			},
		},
	},

	-- {
	-- 	"filipdutescu/renamer.nvim",
	-- 	dependencies = { "nvim-lua/plenary.nvim" },
	-- },
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		opts = {
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true,
				},
			},
			routes = {
				{
					filter = {
						event = "msg_show",
						any = {
							{ find = "%d+L, %d+B" },
							{ find = "; after #%d+" },
							{ find = "; before #%d+" },
						},
					},
					view = "mini",
				},
			},
			presets = {
				bottom_search = true,
				command_palette = true,
				long_message_to_split = true,
				inc_rename = true,
			},
		},
  -- stylua: ignore
  keys = {
    { "<S-Enter>", function() require("noice").redirect(vim.fn.getcmdline()) end, mode = "c", desc = "Redirect Cmdline" },
    { "<leader>snl", function() require("noice").cmd("last") end, desc = "Noice Last Message" },
    { "<leader>snh", function() require("noice").cmd("history") end, desc = "Noice History" },
    { "<leader>sna", function() require("noice").cmd("all") end, desc = "Noice All" },
    { "<leader>snd", function() require("noice").cmd("dismiss") end, desc = "Dismiss All" },
    { "<c-f>", function() if not require("noice.lsp").scroll(4) then return "<c-f>" end end, silent = true, expr = true, desc = "Scroll forward", mode = {"i", "n", "s"} },
    { "<c-b>", function() if not require("noice.lsp").scroll(-4) then return "<c-b>" end end, silent = true, expr = true, desc = "Scroll backward", mode = {"i", "n", "s"}},
  },
	},
	{
		"stevearc/dressing.nvim",
		opts = {},
	},
	{
		"gbprod/yanky.nvim",
		opts = function()
			return require("configs.yanky")
		end,
	},
	{
		"debugloop/telescope-undo.nvim",
		dependencies = { -- note how they're inverted to above example
			{
				"nvim-telescope/telescope.nvim",
				dependencies = { "nvim-lua/plenary.nvim" },
			},
		},
		keys = {
			{ -- lazy style key map
				"<leader>u",
				"<cmd>Telescope undo<cr>",
				desc = "undo history",
			},
		},
		opts = {
			-- don't use `defaults = { }` here, do this in the main telescope spec
			extensions = {
				undo = {
					-- telescope-undo.nvim config, see below
				},
				-- no other extensions here, they can have their own spec too
			},
		},
		config = function(_, opts)
			-- Calling telescope's setup from multiple specs does not hurt, it will happily merge the
			-- configs for us. We won't use data, as everything is in it's own namespace (telescope
			-- defaults, as well as each extension).
			require("telescope").setup(opts)
			require("telescope").load_extension("undo")
		end,
	},
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		opts = {},
		keys = {
			{
				"s",
				mode = { "n", "x", "o" },
				function()
					require("flash").jump()
				end,
				desc = "Flash",
			},
			{
				"S",
				mode = { "n", "x", "o" },
				function()
					require("flash").treesitter()
				end,
				desc = "Flash Treesitter",
			},
			{
				"r",
				mode = "o",
				function()
					require("flash").remote()
				end,
				desc = "Remote Flash",
			},
			{
				"R",
				mode = { "o", "x" },
				function()
					require("flash").treesitter_search()
				end,
				desc = "Treesitter Search",
			},
			{
				"<c-s>",
				mode = { "c" },
				function()
					require("flash").toggle()
				end,
				desc = "Toggle Flash Search",
			},
		},
	},
	{
		"nvim-tree/nvim-tree.lua",
		opts = {
			git = { enable = true },
		},
	},
	-- {
	-- 	"jose-elias-alvarez/null-ls.nvim",
	-- 	opt = function()
	-- 		return require("configs.null-ls")
	-- 	end,
	-- },
	{
		"nvim-neo-tree/neo-tree.nvim",
		branch = "v3.x",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
			"MunifTanjim/nui.nvim",
			-- "3rd/image.nvim", -- Optional image support in preview window: See `# Preview Mode` for more information
		},
	},
	{
		"rmagatti/auto-session",
		config = function()
			require("auto-session").setup({
				log_level = "error",
				-- auto_session_suppress_dirs = { "~/", "~/Downloads", "/" },
			})
		end,
	},
	{
		"zbirenbaum/copilot.lua",
		cmd = "Copilot",
		build = ":Copilot auth",
		opts = {
			suggestion = { enabled = true },
			panel = { enabled = false },
			filetypes = {
				markdown = true,
				help = true,
			},
		},
	},

	{
		"zbirenbaum/copilot-cmp",
		dependencies = "copilot.lua",
		opts = {},
		config = function(_, opts)
			local copilot_cmp = require("copilot_cmp")
			copilot_cmp.setup(opts)

			-- attach cmp source whenever copilot attaches
			-- fixes lazy-loading issues with the copilot cmp source
			-- require("lazyvim.util").lsp.on_attach(function(client)
			-- 	if client.name == "copilot" then
			-- 		copilot_cmp._on_insert_enter({})
			-- 	end
			-- end)
		end,
	},
	-- {
	-- 	"nvim-cmp",
	-- 	dependencies = {
	-- 		{
	-- 			"zbirenbaum/copilot-cmp",
	-- 			dependencies = "copilot.lua",
	-- 			opts = {},
	-- 			config = function(_, opts)
	-- 				local copilot_cmp = require("copilot_cmp")
	-- 				copilot_cmp.setup(opts)
	--
	-- 				-- attach cmp source whenever copilot attaches
	-- 				-- fixes lazy-loading issues with the copilot cmp source
	-- 				-- require("lazyvim.util").lsp.on_attach(function(client)
	-- 				-- 	if client.name == "copilot" then
	-- 				-- 		copilot_cmp._on_insert_enter({})
	-- 				-- 	end
	-- 				-- end)
	-- 			end,
	-- 		},
	-- 	},
	-- },

	{
		"neovim/nvim-lspconfig",
		config = function()
			require("nvchad.configs.lspconfig").defaults()
			require("configs.lspconfig")
		end,
	},

	{
		"williamboman/mason.nvim",
		opts = {
			ensure_installed = {
				"lua-language-server",
				"html-lsp",
				"prettier",
				"stylua",
				"clangd",
				"clang-format",
			},
		},
	},

	{
		"rcarriga/nvim-notify",
		config = function()
			require("configs.notify")
		end,
	},

	{

		"CRAG666/betterTerm.nvim",
		"mateuszwieloch/automkdir.nvim",
		"jghauser/mkdir.nvim",
		"CRAG666/code_runner.nvim",
		"GCBallesteros/jupytext.nvim",

		"theprimeagen/harpoon",
		"lukas-reineke/indent-blankline.nvim", -- add indentation guides even on blank lines "mg979/vim-visual-multi",
		"nvim-lua/plenary.nvim",
		"tpope/vim-fugitive",
		"lervag/vimtex",
		"kazhala/close-buffers.nvim",
		"xiyaowong/link-visitor.nvim",
		"ragnarok22/whereami.nvim",
		"terryma/vim-multiple-cursors",
		"gaborvecsei/usage-tracker.nvim",

		"monaqa/dial.nvim",
		-- neotest
		"nvim-neotest/neotest-python",
		"alfaix/neotest-gtest",
	},

	{
		"yorickpeterse/nvim-pqf",
		event = "VeryLazy",
	},

	{
		"christoomey/vim-tmux-navigator",
		lazy = false,
		cmd = {
			"Tmuxnavigateleft",
			"Tmuxnavigatedown",
			"Tmuxnavigateup",
			"Tmuxnavigateright",
			"Tmuxnavigateprevious",
		},
		keys = {
			{ "<c-h>", "<cmd><c-u>Tmuxnavigateleft<cr>" },
			{ "<c-j>", "<cmd><c-u>Tmuxnavigatedown<cr>" },
			{ "<c-k>", "<cmd><c-u>Tmuxnavigateup<cr>" },
			{ "<c-l>", "<cmd><c-u>Tmuxnavigateright<cr>" },
			{ "<c-\\>", "<cmd><c-u>Tmuxnavigateprevious<cr>" },
		},
	},
	{
		"chomosuke/term-edit.nvim",
		lazy = false, -- or ft = 'toggleterm' if you use toggleterm.nvim
		version = "1.*",
	},
	{
		"nvim-pack/nvim-spectre",
		build = false,
		cmd = "Spectre",
		opts = { open_cmd = "noswapfile vnew" },
    -- stylua: ignore
    keys = {
      { "<leader>sr", function() require("spectre").open() end, desc = "Replace in files (Spectre)" },
    },
	},
	-- {
	-- 	"nvim-telescope/telescope.nvim",
	-- 	cmd = "Telescope",
	-- 	version = false, -- telescope did only one release, so use HEAD for now
	-- 	dependencies = {
	-- 		{
	-- 			"nvim-telescope/telescope-fzf-native.nvim",
	-- 			build = "make",
	-- 			enabled = vim.fn.executable("make") == 1,
	-- 			config = function()
	-- 				on_load("telescope.nvim", function()
	-- 					require("telescope").load_extension("fzf")
	-- 				end)
	-- 			end,
	-- 		},
	-- 	},
	-- 	keys = {
	-- 		{
	-- 			"<leader>,",
	-- 			"<cmd>Telescope buffers sort_mru=true sort_lastused=true<cr>",
	-- 			desc = "Switch Buffer",
	-- 		},
	-- 		{ "<leader>/", telescope("live_grep"), desc = "Grep (root dir)" },
	-- 		{ "<leader>:", "<cmd>Telescope command_history<cr>", desc = "Command History" },
	-- 		{ "<leader><space>", telescope("files"), desc = "Find Files (root dir)" },
	-- 		-- find
	-- 		{ "<leader>fb", "<cmd>Telescope buffers sort_mru=true sort_lastused=true<cr>", desc = "Buffers" },
	-- 		{ "<leader>fc", telescope.config_files(), desc = "Find Config File" },
	-- 		{ "<leader>ff", telescope("files"), desc = "Find Files (root dir)" },
	-- 		{ "<leader>fF", telescope("files", { cwd = false }), desc = "Find Files (cwd)" },
	-- 		{ "<leader>fg", "<cmd>Telescope git_files<cr>", desc = "Find Files (git-files)" },
	-- 		{ "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent" },
	-- 		{ "<leader>fR", telescope("oldfiles", { cwd = vim.loop.cwd() }), desc = "Recent (cwd)" },
	-- 		-- git
	-- 		{ "<leader>gc", "<cmd>Telescope git_commits<CR>", desc = "commits" },
	-- 		{ "<leader>gs", "<cmd>Telescope git_status<CR>", desc = "status" },
	-- 		-- search
	-- 		{ '<leader>s"', "<cmd>Telescope registers<cr>", desc = "Registers" },
	-- 		{ "<leader>sa", "<cmd>Telescope autocommands<cr>", desc = "Auto Commands" },
	-- 		{ "<leader>sb", "<cmd>Telescope current_buffer_fuzzy_find<cr>", desc = "Buffer" },
	-- 		{ "<leader>sc", "<cmd>Telescope command_history<cr>", desc = "Command History" },
	-- 		{ "<leader>sC", "<cmd>Telescope commands<cr>", desc = "Commands" },
	-- 		{ "<leader>sd", "<cmd>Telescope diagnostics bufnr=0<cr>", desc = "Document diagnostics" },
	-- 		{ "<leader>sD", "<cmd>Telescope diagnostics<cr>", desc = "Workspace diagnostics" },
	-- 		{ "<leader>sg", telescope("live_grep"), desc = "Grep (root dir)" },
	-- 		{ "<leader>sG", telescope("live_grep", { cwd = false }), desc = "Grep (cwd)" },
	-- 		{ "<leader>sh", "<cmd>Telescope help_tags<cr>", desc = "Help Pages" },
	-- 		{ "<leader>sH", "<cmd>Telescope highlights<cr>", desc = "Search Highlight Groups" },
	-- 		{ "<leader>sk", "<cmd>Telescope keymaps<cr>", desc = "Key Maps" },
	-- 		{ "<leader>sM", "<cmd>Telescope man_pages<cr>", desc = "Man Pages" },
	-- 		{ "<leader>sm", "<cmd>Telescope marks<cr>", desc = "Jump to Mark" },
	-- 		{ "<leader>so", "<cmd>Telescope vim_options<cr>", desc = "Options" },
	-- 		{ "<leader>sR", "<cmd>Telescope resume<cr>", desc = "Resume" },
	-- 		{ "<leader>sw", telescope("grep_string", { word_match = "-w" }), desc = "Word (root dir)" },
	-- 		{ "<leader>sW", telescope("grep_string", { cwd = false, word_match = "-w" }), desc = "Word (cwd)" },
	-- 		{ "<leader>sw", telescope("grep_string"), mode = "v", desc = "Selection (root dir)" },
	-- 		{ "<leader>sW", telescope("grep_string", { cwd = false }), mode = "v", desc = "Selection (cwd)" },
	-- 		{
	-- 			"<leader>uC",
	-- 			telescope("colorscheme", { enable_preview = true }),
	-- 			desc = "Colorscheme with preview",
	-- 		},
	-- 		{
	-- 			"<leader>ss",
	-- 			function()
	-- 				require("telescope.builtin").lsp_document_symbols({
	-- 					symbols = require("lazyvim.config").get_kind_filter(),
	-- 				})
	-- 			end,
	-- 			desc = "Goto Symbol",
	-- 		},
	-- 		{
	-- 			"<leader>sS",
	-- 			function()
	-- 				require("telescope.builtin").lsp_dynamic_workspace_symbols({
	-- 					symbols = require("lazyvim.config").get_kind_filter(),
	-- 				})
	-- 			end,
	-- 			desc = "Goto Symbol (Workspace)",
	-- 		},
	-- 	},
	-- 	opts = function()
	-- 		local actions = require("telescope.actions")
	--
	-- 		local open_with_trouble = function(...)
	-- 			return require("trouble.providers.telescope").open_with_trouble(...)
	-- 		end
	-- 		local open_selected_with_trouble = function(...)
	-- 			return require("trouble.providers.telescope").open_selected_with_trouble(...)
	-- 		end
	-- 		local find_files_no_ignore = function()
	-- 			local action_state = require("telescope.actions.state")
	-- 			local line = action_state.get_current_line()
	-- 			telescope("find_files", { no_ignore = true, default_text = line })()
	-- 		end
	-- 		local find_files_with_hidden = function()
	-- 			local action_state = require("telescope.actions.state")
	-- 			local line = action_state.get_current_line()
	-- 			telescope("find_files", { hidden = true, default_text = line })()
	-- 		end
	--
	-- 		return {
	-- 			defaults = {
	-- 				prompt_prefix = " ",
	-- 				selection_caret = " ",
	-- 				-- open files in the first window that is an actual file.
	-- 				-- use the current window if no other window is available.
	-- 				get_selection_window = function()
	-- 					local wins = vim.api.nvim_list_wins()
	-- 					table.insert(wins, 1, vim.api.nvim_get_current_win())
	-- 					for _, win in ipairs(wins) do
	-- 						local buf = vim.api.nvim_win_get_buf(win)
	-- 						if vim.bo[buf].buftype == "" then
	-- 							return win
	-- 						end
	-- 					end
	-- 					return 0
	-- 				end,
	-- 				mappings = {
	-- 					i = {
	-- 						["<c-t>"] = open_with_trouble,
	-- 						["<a-t>"] = open_selected_with_trouble,
	-- 						["<a-i>"] = find_files_no_ignore,
	-- 						["<a-h>"] = find_files_with_hidden,
	-- 						["<C-Down>"] = actions.cycle_history_next,
	-- 						["<C-Up>"] = actions.cycle_history_prev,
	-- 						["<C-f>"] = actions.preview_scrolling_down,
	-- 						["<C-b>"] = actions.preview_scrolling_up,
	-- 					},
	-- 					n = {
	-- 						["q"] = actions.close,
	-- 					},
	-- 				},
	-- 			},
	-- 		}
	-- 	end,
	-- },
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		vscode = true,
		opts = {},
    -- stylua: ignore
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "S", mode = { "n", "o", "x" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
		{
			"nvim-telescope/telescope.nvim",
			optional = true,
			opts = function(_, opts)
				local function flash(prompt_bufnr)
					require("flash").jump({
						pattern = "^",
						label = { after = { 0, 0 } },
						search = {
							mode = "search",
							exclude = {
								function(win)
									return vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "TelescopeResults"
								end,
							},
						},
						action = function(match)
							local picker = require("telescope.actions.state").get_current_picker(prompt_bufnr)
							picker:set_selection(match.pos[1] - 1)
						end,
					})
				end
				opts.defaults = vim.tbl_deep_extend("force", opts.defaults or {}, {
					mappings = { n = { s = flash }, i = { ["<c-s>"] = flash } },
				})
			end,
		},
	},
	{
		"RRethy/vim-illuminate",
		event = "VeryLazy",
		opts = {
			delay = 200,
			large_file_cutoff = 2000,
			large_file_overrides = {
				providers = { "lsp" },
			},
		},
		config = function(_, opts)
			require("illuminate").configure(opts)

			local function map(key, dir, buffer)
				vim.keymap.set("n", key, function()
					require("illuminate")["goto_" .. dir .. "_reference"](false)
				end, { desc = dir:sub(1, 1):upper() .. dir:sub(2) .. " Reference", buffer = buffer })
			end

			map("]]", "next")
			map("[[", "prev")

			-- also set it after loading ftplugins, since a lot overwrite [[ and ]]
			vim.api.nvim_create_autocmd("FileType", {
				callback = function()
					local buffer = vim.api.nvim_get_current_buf()
					map("]]", "next", buffer)
					map("[[", "prev", buffer)
				end,
			})
		end,
		keys = {
			{ "]]", desc = "Next Reference" },
			{ "[[", desc = "Prev Reference" },
		},
	},
	{
		"folke/todo-comments.nvim",
		cmd = { "TodoTrouble", "TodoTelescope" },
		event = "VeryLazy",
		config = true,
    -- stylua: ignore
    keys = {
      { "]t", function() require("todo-comments").jump_next() end, desc = "Next todo comment" },
      { "[t", function() require("todo-comments").jump_prev() end, desc = "Previous todo comment" },
      { "<leader>xt", "<cmd>TodoTrouble<cr>", desc = "Todo (Trouble)" },
      { "<leader>xT", "<cmd>TodoTrouble keywords=TODO,FIX,FIXME<cr>", desc = "Todo/Fix/Fixme (Trouble)" },
      { "<leader>st", "<cmd>TodoTelescope<cr>", desc = "Todo" },
      { "<leader>sT", "<cmd>TodoTelescope keywords=TODO,FIX,FIXME<cr>", desc = "Todo/Fix/Fixme" },
    },
	},
}
