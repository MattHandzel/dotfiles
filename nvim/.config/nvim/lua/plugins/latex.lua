return {
	{
		"jbyuki/nabla.nvim",
		ft = { "markdown", "tex", "latex", "plaintex", "norg" },
		keys = {
			{
				"<leader>mm",
				function()
					require("nabla").toggle_virt({ autogen = true, silent = true })
				end,
				desc = "Math: toggle inline LaTeX rendering",
				ft = { "markdown", "tex", "latex", "plaintex", "norg" },
			},
			{
				"<leader>mp",
				function()
					require("nabla").popup()
				end,
				desc = "Math: popup preview under cursor",
				ft = { "markdown", "tex", "latex", "plaintex", "norg" },
			},
		},
		config = function()
			local function enable()
				pcall(function()
					require("nabla").enable_virt({ autogen = true, silent = true })
				end)
			end

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("NablaAutoEnable", { clear = true }),
				pattern = { "markdown", "tex", "latex", "plaintex", "norg" },
				callback = function()
					vim.schedule(enable)
				end,
			})

			vim.schedule(enable)
		end,
	},
}
