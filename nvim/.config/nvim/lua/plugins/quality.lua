return {
	{
		"catppuccin/nvim",
		name = "catppuccin",
		lazy = false,
		priority = 1000,
	},

	{
		"rmagatti/auto-session",
		enabled = false,
	},

	{
		"folke/persistence.nvim",
		lazy = false,
		opts = {
			need = 1,
			branch = true,
		},
		config = function(_, opts)
			local persistence = require("persistence")
			persistence.setup(opts)

			local startup_cwd = vim.uv.cwd()
			local group = vim.api.nvim_create_augroup("ConfigPersistence", { clear = true })
			local function should_restore_last_session()
				if vim.fn.argc() > 0 then
					return false
				end

				local buf = vim.api.nvim_get_current_buf()
				if vim.bo[buf].buftype ~= "" then
					return false
				end

				if vim.api.nvim_buf_get_name(buf) ~= "" then
					return false
				end

				return vim.api.nvim_buf_line_count(buf) == 1
					and vim.api.nvim_get_current_line() == ""
					and not vim.bo[buf].modified
			end

			vim.schedule(function()
				if should_restore_last_session() then
					pcall(persistence.load, { last = true })
				end
			end)

			vim.api.nvim_create_autocmd("VimLeavePre", {
				group = group,
				callback = function()
					if startup_cwd and startup_cwd ~= "" then
						pcall(vim.cmd.cd, startup_cwd)
					end
				end,
			})
		end,
		keys = {
			{
				"<leader>qs",
				function()
					require("persistence").load()
				end,
				desc = "Restore Session",
			},
			{
				"<leader>qS",
				function()
					require("persistence").load({ last = true })
				end,
				desc = "Restore Last Session",
			},
			{
				"<leader>qd",
				function()
					require("persistence").stop()
				end,
				desc = "Stop Session Save",
			},
		},
	},

	{
		"stevearc/oil.nvim",
		cmd = "Oil",
		opts = {
			default_file_explorer = true,
			view_options = {
				show_hidden = true,
			},
		},
		dependencies = { "nvim-tree/nvim-web-devicons" },
	},

	{
		"folke/snacks.nvim",
		keys = function(_, keys)
			local filtered = {}
			for _, key in ipairs(keys or {}) do
				if key[1] ~= "<leader>e" and key[1] ~= "<leader>bd" then
					table.insert(filtered, key)
				end
			end
			return filtered
		end,
	},

	{
		"famiu/bufdelete.nvim",
		keys = {
			{
				"<leader>bd",
				function()
					require("bufdelete").bufdelete(0, false)
				end,
				desc = "Delete Buffer",
			},
			{
				"<leader>bD",
				function()
					require("bufdelete").bufdelete(0, true)
				end,
				desc = "Delete Buffer (Force)",
			},
		},
	},

	{
		"axkirillov/hbac.nvim",
		event = "VeryLazy",
		config = function()
			require("hbac").setup({
				threshold = 15,
				close_command = function(bufnr)
					local ok, bufdelete = pcall(require, "bufdelete")
					if ok then
						bufdelete.bufdelete(bufnr, false)
						return
					end
					vim.api.nvim_buf_delete(bufnr, {})
				end,
			})
		end,
	},

	{
		"monkoose/neocodeium",
		event = "InsertEnter",
		config = function()
			local neocodeium = require("neocodeium")
			neocodeium.setup({
				silent = true,
				filter = function()
					local ok, cmp = pcall(require, "cmp")
					return not (ok and cmp.visible())
				end,
			})

			vim.keymap.set("i", "<A-f>", neocodeium.accept, { desc = "AI Accept" })
			vim.keymap.set("i", "<A-]>", function()
				neocodeium.cycle_or_complete(1)
			end, { desc = "AI Next" })
			vim.keymap.set("i", "<A-[>", function()
				neocodeium.cycle_or_complete(-1)
			end, { desc = "AI Prev" })
			vim.keymap.set("n", "<leader>ua", function()
				require("neocodeium.commands").toggle()
			end, { desc = "Toggle AI Completion" })

			local ok, cmp = pcall(require, "cmp")
			if ok and cmp.event then
				cmp.event:on("menu_opened", function()
					neocodeium.clear()
				end)
			end
		end,
	},

	{
		"olimorris/codecompanion.nvim",
		cmd = {
			"CodeCompanion",
			"CodeCompanionActions",
			"CodeCompanionChat",
			"CodeCompanionCmd",
		},
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-treesitter/nvim-treesitter",
		},
		init = function()
			if not vim.env.CODECOMPANION_TOKEN_PATH or vim.env.CODECOMPANION_TOKEN_PATH == "" then
				vim.env.CODECOMPANION_TOKEN_PATH = vim.fn.expand("~/.config")
			end
		end,
		opts = {
			interactions = {
				chat = { adapter = "copilot" },
				inline = { adapter = "copilot" },
			},
			opts = {
				log_level = "ERROR",
			},
		},
		keys = {
			{ "<leader>aa", "<cmd>CodeCompanionActions<CR>", mode = { "n", "v" }, desc = "AI Actions" },
			{ "<leader>ac", "<cmd>CodeCompanionChat Toggle<CR>", mode = { "n", "v" }, desc = "AI Chat Toggle" },
			{ "<leader>ap", "<cmd>CodeCompanion<CR>", mode = { "n", "v" }, desc = "AI Inline Prompt" },
		},
	},

	{
		"zbirenbaum/copilot.lua",
		opts = function(_, opts)
			opts = opts or {}
			opts.suggestion = opts.suggestion or {}
			opts.suggestion.enabled = false
			opts.panel = opts.panel or {}
			opts.panel.enabled = false
			return opts
		end,
	},
}
