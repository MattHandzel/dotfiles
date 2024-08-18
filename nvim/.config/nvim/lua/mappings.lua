-- add yours here

local map = vim.keymap.set

map("i", "<C-b>", "<ESC>^i", { desc = "Move Beginning of line" })
map("i", "<C-e>", "<End>", { desc = "Move End of line" })

map("n", "<Esc>", "<cmd>noh<CR>", { desc = "General Clear highlights" })

map({ "n", "t" }, "<C-h>", "<C-w>h", { desc = "Switch Window left" })
map({ "n", "t" }, "<C-l>", "<C-w>l", { desc = "Switch Window right" })
map({ "n", "t" }, "<C-j>", "<C-w>j", { desc = "Switch Window down" })
map({ "n", "t" }, "<C-k>", "<C-w>k", { desc = "Switch Window up" })

map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })
map("n", "<C-c>", "<cmd>%y+<CR>", { desc = "File Copy whole" })

map("n", "<leader>ch", "<cmd>NvCheatsheet<CR>", { desc = "Toggle NvCheatsheet" })

-- global lsp mappings
map("n", "<leader>lf", vim.diagnostic.open_float, { desc = "Lsp floating diagnostics" })
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Lsp prev diagnostic" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Lsp next diagnostic" })
map("n", "<leader>dl", vim.diagnostic.setloclist, { desc = "Lsp diagnostic loclist" })

-- tabufline
map("n", "<leader>b", "<cmd>enew<CR>", { desc = "Buffer New" })
map("n", "<leader>x", function()
	require("nvchad.tabufline").close_buffer()
end, { desc = "Buffer Close" })

-- nvimtree
map("n", "<leader>e", "<cmd>Neotree toggle<CR>", { desc = "Neotree Toggle window" })

-- telescope
map("n", "<leader>fw", "<cmd>Telescope live_grep<CR>", { desc = "Telescope Live grep" })
map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Telescope Find buffers" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { desc = "Telescope Help page" })

map("n", "<leader>fo", "<cmd>Telescope oldfiles<CR>", { desc = "Telescope Find oldfiles" })
map("n", "<leader>fz", "<cmd>Telescope current_buffer_fuzzy_find<CR>", { desc = "Telescope Find in current buffer" })
map("n", "<leader>fc", "<cmd>Telescope git_commits<CR>", { desc = "Telescope Git commits" })
map("n", "<leader>fs", "<cmd>Telescope git_status<CR>", { desc = "Telescope Git status" })
map("n", "<leader>ft", "<cmd>Telescope terms<CR>", { desc = "Telescope Pick hidden term" })
-- map("n", "<leader>th", "<cmd>Telescope themes<CR>", { desc = "Telescope Nvchad themes" })
map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Telescope Find files" })
map(
	"n",
	"<leader>fa",
	"<cmd>Telescope find_files follow=true no_ignore=true hidden=true<CR>",
	{ desc = "Telescope Find all files" }
)

-- better indenting
map("v", "<", "<gv")
map("v", ">", ">gv")
-- terminal
map("t", "<Esc>", "<C-\\><C-N>", { desc = "Terminal Escape terminal mode" })

-- new terminals
map("n", "<leader>tv", function()
	require("nvchad.term").new({ pos = "sp", size = 0.3 })
end, { desc = "Terminal New horizontal term" })

map("n", "<leader>th", function()
	require("nvchad.term").new({ pos = "vsp", size = 0.3 })
end, { desc = "Terminal New vertical window" })

-- toggleable
map({ "n", "t" }, "<A-v>", function()
	require("nvchad.term").toggle({ pos = "vsp", id = "vtoggleTerm", size = 0.3 })
end, { desc = "Terminal Toggleable vertical term" })

map({ "n", "t" }, "<A-h>", function()
	require("nvchad.term").toggle({ pos = "sp", id = "htoggleTerm", size = 0.3 })
end, { desc = "Terminal New horizontal term" })

map({ "n", "t" }, "<A-i>", function()
	require("nvchad.term").toggle({ pos = "float", id = "floatTerm" })
end, { desc = "Terminal Toggle Floating term" })

-- map("t", "<ESC>", function()
--   local win = vim.api.nvim_get_current_win()
--   vim.api.nvim_win_close(win, true)
-- end, { desc = "Terminal Close term in terminal mode" })

-- whichkey
map("n", "<leader>wK", "<cmd>WhichKey <CR>", { desc = "Whichkey all keymaps" })

map("n", "<leader>wk", function()
	vim.cmd("WhichKey " .. vim.fn.input("WhichKey: "))
end, { desc = "Whichkey query lookup" })

-- blankline
map("n", "<leader>cc", function()
	local config = { scope = {} }
	config.scope.exclude = { language = {}, node_type = {} }
	config.scope.include = { node_type = {} }
	local node = require("ibl.scope").get(vim.api.nvim_get_current_buf(), config)

	if node then
		local start_row, _, end_row, _ = node:range()
		if start_row ~= end_row then
			vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { start_row + 1, 0 })
			vim.api.nvim_feedkeys("_", "n", true)
		end
	end
end, { desc = "Blankline Jump to current context" })
-- map("n", "<leader>fm", function()
--   require("conform").format()
-- end, { desc = "File Format with conform" })

-- Make it so that when moving we keep the middle of the screen
vim.api.nvim_set_keymap("n", "<C-u>", "<C-u>zz", { noremap = true })
vim.api.nvim_set_keymap("n", "<C-d>", "<C-d>zz", { noremap = true })
vim.api.nvim_set_keymap("n", "N", "Nzzzv", { noremap = true })
vim.api.nvim_set_keymap("n", "n", "nzzzv", { noremap = true })
-- vim.api.nvim_set_keymap("n", "<leader>gD", "<leader>gDzt", { noremap = true })
-- vim.api.nvim_set_keymap("n", "<leader>gd", "<leader>gdzt", { noremap = true })

-- Keymaps that should be there imo
vim.api.nvim_set_keymap("i", "<C-BS>", "<C-w>", { noremap = true })
vim.api.nvim_set_keymap("n", "<C-a>", "gg<S-v>G", { noremap = true })
vim.api.nvim_set_keymap("n", "db", "xdb", { noremap = true })
vim.api.nvim_set_keymap("n", "dB", "xdB", { noremap = true })
map({"n", "v"}, "gg", "ggzz", { noremap = true })
map({"n", "v"}, "G", "Gzz", { noremap = true })
map("v", "/", "y<Esc>/<C-r>\"", { noremap = true })
map("v", "<M-r>", ":'<,'>s/<C-r>\"", { noremap = true })

silent_no_remap = { silent = true, noremap = true }

map("n", "<M-j>", "<cmd>m .+1<CR>==", { desc = "Move line down" })
map("n", "<M-k>", "<cmd>m .-2<CR>==", { desc = "Move line up" })

map("n", "<C-o>", "<C-o>zz", { noremap = true })
map("n", "<C-i>", "<C-i>zz", { noremap = true })

map("n", "<S-H>", ":bprev<CR>", silent_no_remap)
map("n", "<S-L>", ":bnext<CR>", silent_no_remap)
map("n", "<leader>qq", "<cmd>Neotree close<CR><cmd>qa<CR>")
map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Increase window height" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Decrease window height" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Decrease window width" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Increase window width" })

map("n", "n", "'Nn'[v:searchforward].'zv'", { expr = true, desc = "Next search result" })
map("x", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next search result" })
map("o", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next search result" })
map("n", "N", "'nN'[v:searchforward].'zv'", { expr = true, desc = "Prev search result" })
map("x", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev search result" })
map("o", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev search result" })

vim.api.nvim_set_keymap("i", "<C-@>", "<C-\\><C-o>db", { noremap = true })
vim.api.nvim_set_keymap("i", "<C-h>", "<Esc><C-h>", { noremap = true })
vim.api.nvim_set_keymap("n", "<leader>gI", "<leader>gIdzt", { noremap = true })

-- expanding vim keybindings
vim.api.nvim_set_keymap("n", "<M-o>", "o<Esc>", { noremap = true })
vim.api.nvim_set_keymap("n", "<M-O>", "O<Esc>", { noremap = true })

vim.api.nvim_set_keymap('v', '<M-d>', '"_d', { noremap = true, silent = true })
vim.api.nvim_set_keymap('v', '<M-p>', '"_dP', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<M-d>d', '"_d', { noremap = true, silent = true })

-- Map the function to a key combination in visual mode
-- vim.api.nvim_set_keymap("n", "<M-p>", "p", { noremap = true })

map("n", "j", "gj")
map("n", "k", "gk")

map("n", "<leader>ww", "<C-W>p", { desc = "Other window", remap = true })
map("n", "<leader>wd", "<C-W>c", { desc = "Delete window", remap = true })
map("n", "<leader>w_", "<C-W>s", { desc = "Split window below", remap = true })
map("n", "<leader>w|", "<C-W>v", { desc = "Split window right", remap = true })
map("n", "<leader>_", "<C-W>s", { desc = "Split window below", remap = true })
map("n", "<leader>|", "<C-W>v", { desc = "Split window right", remap = true })

-- dial
vim.keymap.set("n", "<leader>+n", function()
	require("dial.map").manipulate("increment", "normal")
end)
vim.keymap.set("n", "<leader>+g", function()
	require("dial.map").manipulate("increment", "gnormal")
end)
vim.keymap.set("v", "<leader>+n", function()
	require("dial.map").manipulate("increment", "visual")
end)
vim.keymap.set("v", "<leader>+g", function()
	require("dial.map").manipulate("increment", "gvisual")
end)

vim.keymap.set("n", "<leader>-n", function()
	require("dial.map").manipulate("decrement", "normal")
end)
vim.keymap.set("n", "<leader>-g", function()
	require("dial.map").manipulate("decrement", "gnormal")
end)
vim.keymap.set("v", "<leader>-n", function()
	require("dial.map").manipulate("decrement", "visual")
end)
vim.keymap.set("v", "<leader>-g", function()
	require("dial.map").manipulate("decrement", "gvisual")
end)

vim.keymap.set("n", "<leader>r", ":RunCode<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rf", ":RunFile<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rft", ":RunFile tab<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rp", ":RunProject<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rc", ":RunClose<CR>", { noremap = true, silent = false })

vim.keymap.set("n", "<leader>rrf", ":CRFiletype<CR>", { noremap = true, silent = false })
vim.keymap.set("n", "<leader>rrp", ":CRProjects<CR>", { noremap = true, silent = false })

vim.keymap.set("n", "<leader>ab", ":DapToggleBreakpoint<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ai", ":DapStepInto<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ao", ":DapStepOut<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ax", ":DapTerminate<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>as", ":DapStepOver<CR>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ar", ":DapContinue<CR>", { noremap = true, silent = true })

-- vim.keymap.set("n", "<leader>m", require("grapple").toggle)
vim.keymap.set("n", "<leader>ha", require("harpoon.mark").add_file, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ht", require("harpoon.ui").toggle_quick_menu, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>hn", require("harpoon.ui").nav_next, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>hp", require("harpoon.ui").nav_prev, { noremap = true, silent = true })
vim.keymap.set("n", "<M-1>", '<cmd>lua require("harpoon.ui").nav_file(1)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<M-2>", '<cmd>lua require("harpoon.ui").nav_file(2)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<M-3>", '<cmd>lua require("harpoon.ui").nav_file(3)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<M-4>", '<cmd>lua require("harpoon.ui").nav_file(4)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<M-5>", '<cmd>lua require("harpoon.ui").nav_file(5)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<M-6>", '<cmd>lua require("harpoon.ui").nav_file(6)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<M-7>", '<cmd>lua require("harpoon.ui").nav_file(7)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<M-8>", '<cmd>lua require("harpoon.ui").nav_file(8)<CR>', { noremap = true, silent = true })
vim.keymap.set("n", "<M-9>", '<cmd>lua require("harpoon.ui").nav_file(9)<CR>', { noremap = true, silent = true })
--
-- vim.keymap.set("n", "<leader>tr", "<cmd> lua require('neotest').run.run()<CR>", { noremap = true, silent = true })
-- vim.keymap.set(
-- 	"n",
-- 	"<leader>tf",
-- 	"<cmd> lua require('neotest').run.run(vim.fn.expand('%'))<CR>",
-- 	{ noremap = true, silent = true }
-- )
-- vim.keymap.set(
-- 	"n",
-- 	"<leader>td",
-- 	"<cmd> lua require('neotest').run.run({strategy = 'dap'})<CR>",
-- 	{ noremap = true, silent = true }
-- )
-- vim.keymap.set("n", "<leader>tx", "<cmd> lua require('neotest').run.stop()<CR>", { noremap = true, silent = true })
-- vim.keymap.set("n", "<leader>ta", "<cmd> lua require('neotest').run.attach()<CR>", { noremap = true, silent = true })
-- vim.keymap.set("n", "<leader>tl", "<cmd> lua require('neotest').run.last()<CR>", { noremap = true, silent = true })
-- -- status window
--
-- vim.keymap.set("n", "<leader>ts", "<cmd> lua require('neotest').status.open()<CR>", { noremap = true, silent = true })
-- vim.keymap.set("n", "<leader>tS", "<cmd> lua require('neotest').summary.open()<CR>", { noremap = true, silent = true })
--
-- vim.keymap.set("n", "<leader>re", function()
-- 	require("betterTerm").send(
-- 		require("code_runner.commands").get_filetype_command(),
-- 		1,
-- 		{ clean = false, interrupt = true }
-- 	)
-- end, { desc = "Excute File" })
--


local betterTerm = require("betterTerm")

-- toggle firts term
vim.keymap.set({ "n", "t" }, "<C-;>", betterTerm.open, { desc = "Open terminal" })
-- Select term focus
vim.keymap.set({ "n" }, "<leader>tt", betterTerm.select, { desc = "Select terminal" })
-- Create new term
local current = 0
vim.keymap.set({ "n" }, "<leader>tn", function()
	betterTerm.open(current)
	current = current + 1
end, { desc = "New terminal" })
betterTerm.setup()

vim.keymap.set("i", "<C-k>", "<Esc>:TmuxNavigateUp<CR>i", { noremap = true, silent = true })
vim.keymap.set("i", "<C-j>", "<Esc>:TmuxNavigateDown<CR>i", { noremap = true, silent = true })
vim.keymap.set("i", "<C-h>", "<Esc>:TmuxNavigateLeft<CR>i", { noremap = true, silent = true })
vim.keymap.set("i", "<C-l>", "<Esc>:TmuxNavigateRight<CR>i", { noremap = true, silent = true })

vim.keymap.set("n", "<leader>ls", require("auto-session.session-lens").search_session, {
	noremap = true,
})
-- vim.keymap.set("n", "<leader>qs", ":SessionRestore<CR>", { noremap = true })
-- vim.api.nvim_set_keymap("i", "<F2>", '<cmd>lua require("renamer").rename()<cr>', { noremap = true, silent = true })
-- vim.api.nvim_set_keymap(
-- 	"n",
-- 	"<leader>cr",
-- 	'<cmd>lua require("renamer").rename()<cr>',
-- 	{ noremap = true, silent = true }
-- )
-- vim.api.nvim_set_keymap(
-- 	"v",
-- 	"<leader>cr",
-- 	'<cmd>lua require("renamer").rename()<cr>',
-- 	{ noremap = true, silent = true }
-- )

-- yanky mappings
vim.keymap.set({ "n", "x" }, "p", "<Plug>(YankyPutAfter)")
vim.keymap.set({ "n", "x" }, "P", "<Plug>(YankyPutBefore)")
vim.keymap.set({ "n", "x" }, "gp", "<Plug>(YankyGPutAfter)")
vim.keymap.set({ "n", "x" }, "gP", "<Plug>(YankyGPutBefore)")

vim.keymap.set("n", "<leader>p", ":YankyRingHistory<CR>")

-- vim.keymap.set("n", "<c-p>", "<Plug>(YankyPreviousEntry)")
-- vim.keymap.set("n", "<c-n>", "<Plug>(YankyNextEntry)")
