local options = {
	lsp_fallback = true,

	formatters_by_ft = {
		lua = { "stylua" },
		cpp = { "clang_format" },
		c = { "clang_format" },
		markdown = { "prettier" },
		python = { "black" },
		py = { "black" },
		nix = { "alejandra" },
		javascript = { "prettier" },
		typescript = { "prettier" },
		json = { "prettier" },
		go = { "gofmt" },
    rust = {"rustfmt"},
	},
}

require("conform").setup(options)
