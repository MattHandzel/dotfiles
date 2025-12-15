vim.g.base46_cache = vim.fn.stdpath("data") .. "/nvchad/base46/"
vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"
vim.g.python3_host_prog = vim.fn.exepath("python3")
vim.g.node_host_prog = "${pkgs.nodejs}/bin/node"
vim.g.mapleader = " "
vim.g.maplocalleader = ","
vim.opt.ruler = false
vim.opt.shortmess:append("FWA")

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
-- dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require("nvchad.autocmds")
require("autocommands")

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
		completeopt = "menu,menuone, noinsert, popup",
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

		["<C-Tab>"] = cmp.mapping.confirm({
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

require("sc-im").setup({
	-- ft = "scim",
	-- include_sc_file = true,
	-- update_sc_from_md = true,
	-- link_fmt = 1,
	-- split = "floating",
	-- float_config = {
	-- 	height = 0.9,
	-- 	width = 0.9,
	-- 	style = "minimal",
	-- 	border = "single",
	-- 	hl = "Normal",
	-- 	blend = 0,
	-- },
})

cmp.setup(options)

require("configs.dap")

function EvalAndReplace()
	-- get visual selection
	local _, csrow, cscol, cerow, cecol = unpack(vim.fn.getpos("'<"))
	local _, _, _, _ = unpack(vim.fn.getpos("'>"))
	local lines = vim.fn.getline(csrow, cerow)

	if #lines == 0 then
		return
	end

	-- if multiple lines, join with spaces
	local text
	if #lines == 1 then
		text = string.sub(lines[1], cscol, cecol)
	else
		lines[1] = string.sub(lines[1], cscol)
		lines[#lines] = string.sub(lines[#lines], 1, cecol)
		text = table.concat(lines, " ")
	end

	-- try evaluating the math expression
	local f, err = load("return " .. text)
	local result
	if f then
		local ok, val = pcall(f)
		if ok and type(val) == "number" then
			result = tostring(val)
		else
			result = "ERR"
		end
	else
		result = "ERR"
	end

	-- replace selection
	vim.api.nvim_buf_set_text(0, csrow - 1, cscol - 1, cerow - 1, cecol, { result })
end

vim.api.nvim_set_keymap("v", "<leader>m", ":lua EvalAndReplace()<CR>", { noremap = true, silent = true })

-- Maybe this should go into a separate file later.
--
-- Searches the current buffer's frontmatter for the 'id:' field.
-- @return string|nil The found ID, or nil if not found.
---
local function get_current_note_id()
	-- Save cursor and window view to restore it later
	local save_view = vim.fn.winsaveview()

	-- Go to the first line to start the search
	vim.cmd("1")

	-- Search for a line starting with 'id:', 'W' means no wrap
	local line_num = vim.fn.search("^id:", "W")

	-- Restore the original view (cursor and window position)
	vim.fn.winrestview(save_view)

	if line_num == 0 then
		-- If search failed (line_num is 0)
		vim.notify("Error: Could not find 'id:' in frontmatter.", vim.log.levels.ERROR, { title = "Yank with ID" })
		return nil
	end

	-- Get the content of the line where 'id:' was found
	local id_line = vim.fn.getline(line_num)

	-- Extract the ID using Lua's string matching
	-- ^id:%s* : matches 'id:' at the start, followed by optional whitespace
	-- (.*)      : captures the rest of the line
	local id = id_line:match("^id:%s*(.*)")

	if id then
		-- Trim any extra whitespace from the captured ID
		return id:match("^%s*(.-)%s*$")
	else
		-- This should be rare if the search succeeded, but it's good practice
		vim.notify("Error: Found 'id:' line but could not parse ID.", vim.log.levels.ERROR, { title = "Yank with ID" })
		return nil
	end
end

---
-- Global function to be called from the keymap.
-- Yanks the visually selected text (from 'v' register)
-- and appends the note ID, then copies to clipboard.
---
function _G.YankSelectedWithNoteID()
	-- 1. Get the note ID from our helper function
	local note_id = get_current_note_id()
	if not note_id then
		return -- Error was already notified
	end

	-- 2. Get the visually selected text (yanked to 'v' register by the keymap)
	local selected_text = vim.fn.getreg("v")
	if not selected_text or selected_text == "" then
		vim.notify(
			"Error: No text selected or 'v' register is empty.",
			vim.log.levels.ERROR,
			{ title = "Yank with ID" }
		)
		return
	end

	-- 3. Clean up the selected text
	--    - Replace one or more newlines/carriage returns with a single space
	--    - Trim leading/trailing whitespace
	local clean_text = selected_text:gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")

	-- 4. Format the final string as requested
	local final_string = string.format("%s [[%s]]", clean_text, note_id)

	-- 5. Set the system clipboard register '+'
	vim.fn.setreg("+", final_string)

	-- 6. Provide success feedback
	vim.notify("Copied link to clipboard!", vim.log.levels.INFO, { title = "Yank with ID" })
end

-- Map 'L' in visual mode to yank to 'v' register, then call our function
vim.keymap.set(
	"v",
	"L",
	'"vy:lua _G.YankSelectedWithNoteID()<CR>',
	{ silent = true, desc = "Yank text with note ID link" }
)
