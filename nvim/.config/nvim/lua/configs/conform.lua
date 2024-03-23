local options = {
	lsp_fallback = true,

	formatters_by_ft = {
		lua = { "stylua" },
		cpp = { "clang_format" },
		c = { "clang_format" },
	},
}

require("conform").setup(options)
