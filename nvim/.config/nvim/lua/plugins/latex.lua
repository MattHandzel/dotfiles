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

			-- Auto-enable on REAL LaTeX filetypes only — deliberately NOT markdown.
			-- nabla's parser asserts ("No matching closing bracket", ascii.lua:1867)
			-- on any `\cmd{` whose brace it can't pair. The vault is 13k+ notes of
			-- prose where `$`, `{` and `\` appear constantly outside math, so
			-- auto-rendering every markdown buffer turned a math feature into a
			-- steady stream of parser errors. `silent = true` does not cover it and
			-- neither does the pcall below: autogen re-renders on later text
			-- changes, outside this call stack, so the assert escapes as a message.
			-- Markdown keeps nabla ON DEMAND via <leader>mm / <leader>mp above.
			-- To go back to auto-rendering markdown, add "markdown" to `pattern`.
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("NablaAutoEnable", { clear = true }),
				pattern = { "tex", "latex", "plaintex" },
				callback = function()
					vim.schedule(enable)
				end,
			})
		end,
	},
}
