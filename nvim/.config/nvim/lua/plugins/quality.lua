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

			vim.api.nvim_create_autocmd("VimEnter", {
				group = group,
				callback = function()
					if vim.fn.argc() == 0 and vim.fn.line2byte("$") == -1 then
						persistence.load({ last = true })
					end
				end,
			})

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
				if key[1] ~= "<leader>e" then
					table.insert(filtered, key)
				end
			end
			return filtered
		end,
	},

	{
		"axkirillov/hbac.nvim",
		event = "VeryLazy",
		config = function()
			require("hbac").setup()
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
