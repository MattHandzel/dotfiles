local options = {
	lsp_fallback = true,

	formatters_by_ft = {
		lua = { "stylua" },
		cpp = { "clang-format" },
		c = { "clang-format" },
	},
}

require("conform").setup(options)
