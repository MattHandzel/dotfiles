local null_ls = require("null-ls")

local opts = {
    sources = {
        null_ls.builtins.formatting.stylua,
        null_ls.builtins.formatting.clang_format,
        null_ls.builtins.diagnostics.eslint,
        null_ls.builtins.completion.spell,

    },
}

return opts;
