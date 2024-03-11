vim.g.base46_cache = vim.fn.stdpath("data") .. "/nvchad/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.loop.fs_stat(lazypath) then
	local repo = "https://github.com/folke/lazy.nvim.git"
	vim.fn.system({ "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath })
end

vim.opt.rtp:prepend(lazypath)
local lazy_config = require("configs.lazy")
-- load plugins
require("lazy").setup({
	{
		"NvChad/NvChad",
		lazy = false,
		branch = "v2.5",
		import = "nvchad.plugins",
		config = function()
			require("options")
		end,
	},
	{ import = "plugins" },
}, lazy_config)

-- load theme
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require("nvchad.autocmds")

vim.schedule(function()
	require("mappings")
end)

require("configs.setups")
local function customize_colorscheme()
	-- Use Vim script syntax with vim.cmd
	vim.cmd([[
    highlight LineNr ctermfg=White guifg=#cacaca
    highlight CursorLineNr ctermfg=Yellow guifg=#ffff00
    highlight Comment ctermfg=Gray guifg=#b8a8af
]])
end

customize_colorscheme()
vim.defer_fn(function()
	vim.api.nvim_command("highlight @comment ctermfg=Gray guifg=#a898a8")
end, 1000) -- Adjust the delay time in milliseconds (1000ms = 1s)

local has_words_before = function()
	if vim.api.nvim_buf_get_option(0, "buftype") == "prompt" then
		return false
	end
	local line, col = unpack(vim.api.nvim_win_get_cursor(0))
	return col ~= 0 and vim.api.nvim_buf_get_text(0, line - 1, 0, line - 1, col, {})[1]:match("^%s*$") == nil
end

local cmp = require("cmp")

dofile(vim.g.base46_cache .. "cmp")

local cmp_ui = require("nvconfig").ui.cmp
local cmp_style = cmp_ui.style

local field_arrangement = {
	atom = { "kind", "abbr", "menu" },
	atom_colored = { "kind", "abbr", "menu" },
}

local formatting_style = {
	-- default fields order i.e completion word + item.kind + item.kind icons
	fields = field_arrangement[cmp_style] or { "abbr", "kind", "menu" },

	format = function(_, item)
		local icons = require("nvchad.icons.lspkind")
		local icon = (cmp_ui.icons and icons[item.kind]) or ""

		if cmp_style == "atom" or cmp_style == "atom_colored" then
			icon = " " .. icon .. " "
			item.menu = cmp_ui.lspkind_text and "   (" .. item.kind .. ")" or ""
			item.kind = icon
		else
			icon = cmp_ui.lspkind_text and (" " .. icon .. " ") or icon
			item.kind = string.format("%s %s", icon, cmp_ui.lspkind_text and item.kind or "")
		end

		return item
	end,
}

local function border(hl_name)
	return {
		{ "╭", hl_name },
		{ "─", hl_name },
		{ "╮", hl_name },
		{ "│", hl_name },
		{ "╯", hl_name },
		{ "─", hl_name },
		{ "╰", hl_name },
		{ "│", hl_name },
	}
end

local options = {
	completion = {
		completeopt = "menu,menuone",
	},

	window = {
		completion = {
			side_padding = (cmp_style ~= "atom" and cmp_style ~= "atom_colored") and 1 or 0,
			winhighlight = "Normal:CmpPmenu,CursorLine:CmpSel,Search:None",
			scrollbar = false,
		},
		documentation = {
			border = border("CmpDocBorder"),
			winhighlight = "Normal:CmpDoc",
		},
	},
	snippet = {
		expand = function(args)
			require("luasnip").lsp_expand(args.body)
		end,
	},

	formatting = formatting_style,

	mapping = {
		["<C-Space>"] = cmp.mapping.complete(),
		["<C-e>"] = cmp.mapping.close(),
		["<CR>"] = nil,

		["<Tab>"] = cmp.mapping.confirm({
			behavior = cmp.ConfirmBehavior.Insert,
			select = true,
		}),

		["<Down>"] = cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_next_item()
			elseif require("luasnip").expand_or_jumpable() then
				vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Plug>luasnip-expand-or-jump", true, true, true), "")
			else
				fallback()
			end
		end, { "i", "s" }),

		["<Up>"] = cmp.mapping(function(fallback)
			if cmp.visible() then
				cmp.select_prev_item()
			elseif require("luasnip").jumpable(-1) then
				vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<Plug>luasnip-jump-prev", true, true, true), "")
			else
				fallback()
			end
		end, { "i", "s" }),
	},
	sources = {
		{ name = "nvim_lsp" },
		{ name = "luasnip" },
		{ name = "buffer" },
		{ name = "nvim_lua" },
		{ name = "path" },
		{ name = "copilot.lua" },
		{ name = "copilot" },
		{ name = "copilot.vim" },
	},
}

if cmp_style ~= "atom" and cmp_style ~= "atom_colored" then
	options.window.completion.border = border("CmpBorder")
end
require("copilot_cmp")
cmp.setup(options)
