-- add yours here
local map = vim.keymap.set

map("i", "<C-b>", "<ESC>^i", { desc = "Move Beginning of line" })
map("i", "<C-e>", "<End>", { desc = "Move End of line" })

map("n", "<Esc>", "<cmd>noh<CR>", { desc = "General Clear highlights" })

-- map({ "n", "t" }, "<C-h>", "<C-w>h", { desc = "Switch Window left" })
-- map({ "n", "t" }, "<C-l>", "<C-w>l", { desc = "Switch Window right" })
-- map({ "n", "t" }, "<C-j>", "<C-w>j", { desc = "Switch Window down" })
-- map({ "n", "t" }, "<C-k>", "<C-w>k", { desc = "Switch Window up" })

map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save file" })
map("n", "<C-c>", "<cmd>%y+<CR>", { desc = "File Copy whole" })

-- <leader>y — yank the identity of the thing under the cursor: note id,
-- wikilink, path, path:line, URL. <leader>yp (absolute path) moved here from
-- this file so every yank map lives in one place. See lua/configs/yank.lua.
require("configs.yank").setup()

map("n", "<leader>ch", "<cmd>NvCheatsheet<CR>", { desc = "Toggle NvCheatsheet" })

-- global lsp mappings
map("n", "<leader>lf", vim.diagnostic.open_float, { desc = "Lsp floating diagnostics" })
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Lsp prev diagnostic" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Lsp next diagnostic" })
map("n", "<leader>dl", vim.diagnostic.setloclist, { desc = "Lsp diagnostic loclist" })
map("n", "<leader>uD", "<cmd>DiagnosticsToggle<CR>", { desc = "Toggle diagnostics" })
map("n", "<leader>bc", "<cmd>Hbac close_unpinned<CR>", { desc = "Close Unpinned Buffers" })

-- tabufline
-- map("n", "<leader>b", "<cmd>enew<CR>", { desc = "Buffer New" })
-- map("n", "<leader>x", function()
--   require("nvchad.tabufline").close_buffer()
-- end, { desc = "Buffer Close" })

local function open_oil()
	local lazy_ok, lazy = pcall(require, "lazy")
	if lazy_ok then
		pcall(lazy.load, { plugins = { "oil.nvim" } })
	end

	local oil_ok, oil = pcall(require, "oil")
	if oil_ok then
		oil.open()
		return
	end

	vim.notify("Oil is not available", vim.log.levels.ERROR)
end

map("n", "<leader>e", open_oil, { desc = "Oil Explorer" })

map("n", "<leader>E", function()
	local lazy_ok, lazy = pcall(require, "lazy")
	if lazy_ok then
		pcall(lazy.load, { plugins = { "oil.nvim" } })
	end
	local oil_ok, oil = pcall(require, "oil")
	if oil_ok then
		oil.open_float()
		return
	end
	vim.notify("Oil is not available", vim.log.levels.ERROR)
end, { desc = "Oil Explorer (float)" })

-- File actions (also bound to gD/gA inside oil, see lua/configs/file-actions.lua)
map("n", "<leader>fD", function()
	require("configs.file-actions").delete()
end, { desc = "Trash current file" })
map("n", "<leader>fA", function()
	require("configs.file-actions").archive()
end, { desc = "Move current file to archive/" })

-- telescope
-- local telescope_builtin = require("telescope.builtin")
-- map("n", "<leader>fw", "<cmd>Telescope live_grep<CR>", { desc = "Telescope Live grep" })
-- map("n", "<leader>fb", "<cmd>Telescope buffers<CR>", { desc = "Telescope Find buffers" })
-- map("n", "<leader>fh", "<cmd>Telescope help_tags<CR>", { desc = "Telescope Help page" })
-- map("n", "<leader>fs", telescope_builtin.lsp_document_symbols, { desc = "Telescope Help page" })
-- map("n", "<leader>fS", telescope_builtin.lsp_dynamic_workspace_symbols, { desc = "Telescope Help page" })
-- map("n", "<leader>fo", "<cmd>Telescope oldfiles<CR>", { desc = "Telescope Find oldfiles" })
-- map("n", "<leader>fz", "<cmd>Telescope current_buffer_fuzzy_find<CR>", { desc = "Telescope Find in current buffer" })
-- map("n", "<leader>fgc", "<cmd>Telescope git_commits<CR>", { desc = "Telescope Git commits" })
-- map("n", "<leader>fgs", "<cmd>Telescope git_status<CR>", { desc = "Telescope Git status" })
-- -- map("n", "<leader>ft", "<cmd>Telescope terms<CR>", { desc = "Telescope Pick hidden term" })
-- -- map("n", "<leader>th", "<cmd>Telescope themes<CR>", { desc = "Telescope Nvchad themes" })
-- map("n", "<leader>fa", "<cmd>Telescope find_files<cr>", { desc = "Telescope Find files" })
-- map(
--   "n",
--   "<leader>ff",
--   "<cmd>Telescope find_files follow=true no_ignore=true hidden=true<CR>",
--   { desc = "Telescope Find all files" }
-- )

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
-- NOTE: n/N are NOT mapped here. They are mapped further down (search for
-- `v:searchforward`) to the direction-stable variant, which silently overrode
-- these two lines. Two definitions of the same key is how you end up debugging
-- a mapping that is not the one you are reading.
-- vim.api.nvim_set_keymap("n", "<leader>gD", "<leader>gDzt", { noremap = true })
-- vim.api.nvim_set_keymap("n", "<leader>gd", "<leader>gdzt", { noremap = true })
--

-- Keymaps that should be there imo
vim.api.nvim_set_keymap("i", "<C-BS>", "<C-w>", { noremap = true })
vim.api.nvim_set_keymap("n", "<C-a>", "gg<S-v>G", { noremap = true })
vim.api.nvim_set_keymap("n", "db", "xdb", { noremap = true })
vim.api.nvim_set_keymap("n", "dB", "xdB", { noremap = true })
map({ "n", "v" }, "gg", "ggzz", { noremap = true })
map({ "n", "v" }, "G", "Gzz", { noremap = true })
-- Search for the visual selection.
--
-- This used to be `y<Esc>/<C-r>"`, which pasted the raw selection into the
-- search line and interpreted it as a REGEX. Any selection containing a
-- metacharacter therefore searched for the wrong thing or blew up -- selecting
-- `+admin` and hitting `/` is what produced `E486: Pattern not found: +admin`,
-- because the pattern never matched the literal text it came from. It also
-- silently corrupted the search on `.`, `*`, `[`, and `\`.
--
-- Now: yank via a scratch register (leaving " untouched), prefix with \V
-- (very-nomagic) and escape backslashes, so the selection always searches
-- literally. Being the only occurrence reports a tidy message instead of a
-- red E486.
map("x", "/", function()
	local save, savetype = vim.fn.getreg("z"), vim.fn.getregtype("z")
	vim.cmd('noautocmd silent normal! "zy')
	local sel = vim.fn.getreg("z")
	vim.fn.setreg("z", save, savetype)

	-- A search pattern cannot span lines, so use the first line of the selection.
	sel = vim.split(sel, "\n", { plain = true })[1] or ""
	if sel == "" then
		return
	end

	local pattern = "\\V" .. vim.fn.escape(sel, "\\")
	vim.fn.setreg("/", pattern)
	vim.fn.histadd("search", pattern)
	vim.o.hlsearch = true

	if not pcall(vim.cmd, "normal! n") then
		vim.notify("Only occurrence of: " .. sel, vim.log.levels.INFO)
	end
end, { noremap = true, silent = true, desc = "Search for visual selection (literal)" })

-- Substitute WITHIN the selected lines, prefilled with the selection as the
-- pattern. Same \V escaping rationale as above.
--
-- The range is written out as concrete line numbers rather than `'<,'>`: a
-- literal `'<,'>` is resolved when the command runs, so if the buffer has
-- shrunk since those marks were set it raises `E19: Mark has invalid line
-- number`. Numbers captured here cannot go stale.
map("x", "<M-r>", function()
	local save, savetype = vim.fn.getreg("z"), vim.fn.getregtype("z")
	vim.cmd('noautocmd silent normal! "zy')
	local sel = vim.fn.getreg("z")
	vim.fn.setreg("z", save, savetype)

	-- Clamp into [1, last]: line() returns 0 for an unset mark, and `:0,0s/`
	-- is itself an invalid range.
	local last = vim.api.nvim_buf_line_count(0)
	local first_line = math.max(1, math.min(vim.fn.line("'<"), last))
	local last_line = math.max(first_line, math.min(vim.fn.line("'>"), last))

	sel = vim.split(sel, "\n", { plain = true })[1] or ""
	local pattern = sel ~= "" and ("\\V" .. vim.fn.escape(sel, "\\/")) or ""
	vim.api.nvim_feedkeys((":%d,%ds/%s/"):format(first_line, last_line, pattern), "n", false)
end, { noremap = true, desc = "Substitute within visual selection" })

local silent_no_remap = { silent = true, noremap = true }

map("n", "<M-j>", "<cmd>m .+1<CR>==", { desc = "Move line down" })
map("n", "<M-k>", "<cmd>m .-2<CR>==", { desc = "Move line up" })

map("n", "<C-o>", "<C-o>zz", { noremap = true })
map("n", "<C-i>", "<C-i>zz", { noremap = true })

map("n", "<S-H>", ":bprev<CR>", silent_no_remap)
map("n", "<S-L>", ":bnext<CR>", silent_no_remap)
map("n", "<leader>qq", "<cmd>qa<CR>")
map("n", "<leader>qw", "<cmd>wqa<CR>")
map("n", "<leader>q!", "<cmd>qa!<CR>")
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
-- vim.api.nvim_set_keymap("i", "<C-h>", "<Esc><C-h>", { noremap = true })
vim.api.nvim_set_keymap("n", "<leader>gI", "<leader>gIdzt", { noremap = true })

-- expanding vim keybindings
vim.api.nvim_set_keymap("n", "<M-o>", "o<Esc>", { noremap = true })
vim.api.nvim_set_keymap("n", "<M-O>", "O<Esc>", { noremap = true })

vim.api.nvim_set_keymap("v", "<M-d>", '"_d', { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<M-p>", '"_dp', { noremap = true, silent = true })
vim.api.nvim_set_keymap("v", "<M-P>", '"_dP', { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<M-d>d", '"_d', { noremap = true, silent = true })

-- Map the function to a key combination in visual mode
-- vim.api.nvim_set_keymap("n", "<M-p>", "p", { noremap = true })

local function smart_movement(key)
	return function()
		if vim.v.count == 0 then
			return "g" .. key
		else
			return key
		end
	end
end

vim.keymap.set("n", "j", smart_movement("j"), { expr = true })
vim.keymap.set("n", "k", smart_movement("k"), { expr = true })

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
vim.keymap.set("n", "<leader>am", function()
	local ok, dap_python = pcall(require, "dap-python")
	if ok then
		dap_python.test_method()
		return
	end
	vim.notify("nvim-dap-python is not available", vim.log.levels.WARN)
end, { desc = "Debug Python Test Method" })
vim.keymap.set("n", "<leader>aM", function()
	local ok, dap_python = pcall(require, "dap-python")
	if ok then
		dap_python.test_class()
		return
	end
	vim.notify("nvim-dap-python is not available", vim.log.levels.WARN)
end, { desc = "Debug Python Test Class" })
vim.keymap.set("v", "<leader>am", function()
	local ok, dap_python = pcall(require, "dap-python")
	if ok then
		dap_python.debug_selection()
		return
	end
	vim.notify("nvim-dap-python is not available", vim.log.levels.WARN)
end, { desc = "Debug Python Selection" })

-- vim.keymap.set("n", "<leader>m", require("grapple").toggle)
vim.keymap.set("n", "<leader>ha", require("harpoon.mark").add_file, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>ht", require("harpoon.ui").toggle_quick_menu, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>hn", require("harpoon.ui").nav_next, { noremap = true, silent = true })
vim.keymap.set("n", "<leader>hp", require("harpoon.ui").nav_prev, { noremap = true, silent = true })
vim.keymap.set("n", "<M-1>", function()
	require("harpoon.ui").nav_file(1)
end, { noremap = true, silent = true })
vim.keymap.set("n", "<M-2>", function()
	require("harpoon.ui").nav_file(2)
end, { noremap = true, silent = true })
vim.keymap.set("n", "<M-3>", function()
	require("harpoon.ui").nav_file(3)
end, { noremap = true, silent = true })
vim.keymap.set("n", "<M-4>", function()
	require("harpoon.ui").nav_file(4)
end, { noremap = true, silent = true })
vim.keymap.set("n", "<M-5>", function()
	require("harpoon.ui").nav_file(5)
end, { noremap = true, silent = true })
vim.keymap.set("n", "<M-6>", function()
	require("harpoon.ui").nav_file(6)
end, { noremap = true, silent = true })
vim.keymap.set("n", "<M-7>", function()
	require("harpoon.ui").nav_file(7)
end, { noremap = true, silent = true })
vim.keymap.set("n", "<M-8>", function()
	require("harpoon.ui").nav_file(8)
end, { noremap = true, silent = true })
vim.keymap.set("n", "<M-9>", function()
	require("harpoon.ui").nav_file(9)
end, { noremap = true, silent = true })

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

vim.keymap.set("n", "<leader>re", function()
	require("betterTerm").send(
		require("code_runner.commands").get_filetype_command(),
		1,
		{ clean = false, interrupt = true }
	)
end, { desc = "Excute File" })

local function with_module(name, fn)
	local ok, mod = pcall(require, name)
	if not ok then
		vim.notify("Missing plugin module: " .. name, vim.log.levels.WARN)
		return
	end
	fn(mod)
end

vim.keymap.set({ "n", "t" }, "<C-;>", function()
	with_module("betterTerm", function(better_term)
		better_term.open()
	end)
end, { desc = "Open terminal" })

vim.keymap.set({ "n" }, "<leader>tt", function()
	with_module("betterTerm", function(better_term)
		better_term.select()
	end)
end, { desc = "Select terminal" })

local current = 0
vim.keymap.set({ "n" }, "<leader>tn", function()
	with_module("betterTerm", function(better_term)
		better_term.open(current)
		current = current + 1
	end)
end, { desc = "New terminal" })

vim.schedule(function()
	pcall(function()
		require("betterTerm").setup()
	end)
end)

vim.keymap.set({ "i", "n", "t" }, "<C-k>", "<cmd>TmuxNavigateUp<CR>", { noremap = true, silent = true })
vim.keymap.set({ "i", "n", "t" }, "<C-j>", "<cmd>TmuxNavigateDown<CR>", { noremap = true, silent = true })
vim.keymap.set({ "i", "n", "t" }, "<C-h>", "<cmd>TmuxNavigateLeft<CR>", { noremap = true, silent = true })
vim.keymap.set({ "i", "n", "t" }, "<C-l>", "<cmd>TmuxNavigateRight<CR>", { noremap = true, silent = true })

-- Session restore (persistence.nvim; sessions auto-save on exit)
vim.keymap.set("n", "<leader>qs", function()
	require("persistence").load()
end, { noremap = true, desc = "Restore session for cwd" })
vim.keymap.set("n", "<leader>ql", function()
	require("persistence").load({ last = true })
end, { noremap = true, desc = "Restore last session" })
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

vim.keymap.set("n", "<leader>c?", function()
	with_module("CopilotChat", function(copilot_chat)
		copilot_chat.toggle()
	end)
end, { desc = "Copilot Chat Toggle" })

-- vim.keymap.set("n", "<c-p>", "<Plug>(YankyPreviousEntry)")
-- vim.keymap.set("n", "<c-n>", "<Plug>(YankyNextEntry)")
--
--
--#region
--
--
--
vim.keymap.set("i", "C-Z", "<Esc>ui", { noremap = true })

-- Obsidian
--
vim.keymap.set("n", "<leader>gl", "<cmd>ObsidianFollowLink<CR>i", { noremap = true })
vim.keymap.set("n", "<leader>od", "<cmd>ObsidianDailies<CR>", { noremap = true })
vim.keymap.set("n", "<leader>op", "<cmd>ObsidianPasteImg<CR>i", { noremap = true })
-- Visual mode: extract the highlighted text into a new note. `:` prefills the
-- `'<,'>` range so ObsidianExtractNote receives the selection.
vim.keymap.set("x", "<leader>oe", ":ObsidianExtractNote<CR>", { noremap = true, silent = true, desc = "Obsidian Extract Note from selection" })

-- <leader>p: paste a clipboard image through the Obsidian flow (same one the
-- insert-mode <C-v> routes to): name prompt with timestamp default → confirm →
-- saved under assets/imgs/ → embed link inserted. This replaced a hand-rolled
-- PasteClipboardImage() that wrote <timestamp>.png next to the note, which is
-- against the vault's assets convention.
vim.keymap.set("n", "<leader>p", "<cmd>ObsidianPasteImg<CR>", { noremap = true, silent = true, desc = "Paste clipboard image into assets/imgs" })

-- Review pickers: like ObsidianDailies but for past weekly/quarterly/yearly
-- reviews (the /weekly-review family writes them to capture/), newest first.
local function review_picker(kind, glob)
	local files = vim.fn.globpath(vim.fn.expand("~/Obsidian/Main/capture"), glob, false, true)
	table.sort(files, function(a, b)
		return a > b
	end)
	if #files == 0 then
		vim.notify("No " .. kind .. " reviews found in capture/", vim.log.levels.WARN)
		return
	end
	local pickers = require("telescope.pickers")
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	pickers
		.new({}, {
			prompt_title = kind .. " reviews",
			finder = finders.new_table({
				results = files,
				entry_maker = function(path)
					local name = vim.fn.fnamemodify(path, ":t:r")
					return { value = path, display = name, ordinal = name, path = path }
				end,
			}),
			sorter = conf.generic_sorter({}),
			previewer = conf.file_previewer({}),
		})
		:find()
end

vim.keymap.set("n", "<leader>ow", function()
	review_picker("Weekly", "weekly-review-*.md")
end, { noremap = true, desc = "Weekly reviews picker" })
vim.keymap.set("n", "<leader>oq", function()
	review_picker("Quarterly", "quarterly-review-*.md")
end, { noremap = true, desc = "Quarterly reviews picker" })
vim.keymap.set("n", "<leader>oy", function()
	review_picker("Yearly", "yearly-review-*.md")
end, { noremap = true, desc = "Yearly reviews picker" })

-- Open the current quarter's goals (areas/goals/YYYY-qN.md, falling back to
-- the -vision note). If neither exists, opens the plan path so :w creates it
-- (fill it from templates/quarterly-goals.md).
vim.keymap.set("n", "<leader>og", function()
	local t = os.date("*t")
	local base = string.format("%d-q%d", t.year, math.ceil(t.month / 3))
	local dir = vim.fn.expand("~/Obsidian/Main/areas/goals/")
	local path = dir .. base .. ".md"
	if vim.fn.filereadable(path) == 0 and vim.fn.filereadable(dir .. base .. "-vision.md") == 1 then
		path = dir .. base .. "-vision.md"
	end
	vim.cmd.edit(path)
end, { noremap = true, desc = "Current quarter goals" })

vim.keymap.set("n", "<leader>ot", ":ObsidianTemplate<CR>")
local make_reflection = function()
	-- 1. Define your date format and command
	--    (Use "gdate" here if you are on macOS and need nanoseconds)
	local date_cmd = "date -u +'%Y-%m-%dT%H:%M:%S.%6N+00:00'"

	-- 2. Get the timestamp from the shell
	--    vim.fn.system() does NOT have the same '%' problem as '!'
	local timestamp = vim.fn.system(date_cmd)
	timestamp = vim.fn.trim(timestamp) -- Remove the trailing newline

	-- 3. Define your source and destination paths
	local template = vim.fn.expand("~/notes/templates/task-template.md")
	local destination_dir = vim.fn.expand("~/notes/capture/raw_capture/")
	local destination_file = destination_dir .. timestamp .. ".md"

	-- 4. Use NeoVim's built-in file copy
	--    This is better than shelling out to 'cp'
	vim.loop.fs_copyfile(template, destination_file)

	print("Template copied to: " .. destination_file)

	-- now open the file with `:edit`
	vim.api.nvim_command(":edit " .. destination_file)
	vim.api.nvim_command(":write")
end

vim.keymap.set("n", "<leader>or", function()
	make_reflection()
end, { noremap = true })

map("n", "<leader>of", "<cmd>ObsidianTOC<CR>", { desc = "Obsidian Find" })

-- text-case
--<CMD>lua require('textcase').current_word('to_snake_case')<CR>
--
-- enabled_methods = {
--    "to_upper_case",
--    "to_lower_case",
--    "to_snake_case",
--    "to_dash_case",
--    "to_title_dash_case",
--    "to_constant_case",
--    "to_dot_case",
--    "to_comma_case",
--    "to_phrase_case",
--    "to_camel_case",
--    "to_pascal_case",
--    "to_title_case",
--    "to_path_case",
--    "to_upper_phrase_case",
--    "to_lower_phrase_case",
--  },

local text_case_mappings = {
	to_upper_case = "gaU",
	to_lower_case = "gaL",
	to_snake_case = "ga_",
	to_dash_case = "ga-",
	to_title_dash_case = "ga=",
	to_constant_case = "gaC",
	to_dot_case = "ga.",
	to_comma_case = "ga,",
	to_phrase_case = "gaP",
	to_camel_case = "gaC",
	to_pascal_case = "gaP",
	to_title_case = "gaT",
	to_path_case = "ga/",
	to_upper_phrase_case = "gau",
	to_lower_phrase_case = "gal",
}

for method, keymap in pairs(text_case_mappings) do
	vim.keymap.set(
		"n",
		keymap,
		string.format("<cmd>lua require('textcase').current_word('%s')<CR>", method),
		{ noremap = true }
	)
	vim.keymap.set(
		"x",
		keymap,
		string.format("<cmd>lua require('textcase').current_word('%s')<CR>", method),
		{ noremap = true }
	)
end

vim.keymap.set("n", "ga?", "<cmd>TextCaseOpenTelescope<CR>", { noremap = true })

vim.keymap.set("n", "<leader>nl", "<cmd>SemanticSearch<CR>", { noremap = true })

vim.keymap.set("n", "<leader>sc", function()
	with_module("sc-im", function(sc_im)
		sc_im.open_in_scim()
	end)
end, { noremap = true, silent = true, desc = "Open in sc-im" })

vim.keymap.set("n", "<leader>cf", "<cmd>ClaudeFix<CR>", { noremap = true, silent = true, desc = "ClaudeFix: launch Claude to fix errors/warnings" })

-- Wispr Flow push-to-talk (Ctrl+Super+F12) and polish (Ctrl+F12+1).
-- Wispr's Linux port reads the keyboard via evdev, so it fires on the chord but
-- cannot consume it — the compositor still delivers the key to the focused
-- window, and Neovim, having no mapping and no printable form for it, inserted
-- the literal "<C-D-F12>" into the buffer. Swallow it in every mode.
for _, key in ipairs({ "<C-D-F12>", "<C-F12>" }) do
	vim.keymap.set({ "n", "i", "v", "x", "s", "o", "c", "t" }, key, "<Nop>", { silent = true })
end

-- Ctrl+V pastes the system clipboard in insert (and cmdline) mode.
-- This shadows i_CTRL-V (insert-literal-character, e.g. <C-v>u00e9 or a raw
-- tab), so that behavior moves to <C-q> — Vim's own documented alternative.
--
-- The insert-mode side is a function, not <C-r><C-o>+, for two reasons:
--  1. An IMAGE in the clipboard + a markdown buffer routes to
--     :ObsidianPasteImg (name prompt with timestamp default → confirm →
--     save under assets/imgs/ → embed link) instead of inserting nothing.
--  2. TEXT is scrubbed of invalid UTF-8 before insertion. Neovim passes raw
--     register bytes straight into the LSP didChange JSON, and one invalid
--     byte makes harper-ls answer `-32700 Parse error` and die
--     ("LSP[harper_ls]: Error INVALID_SERVER_MESSAGE", 2026-08-25).
--     nvim_paste keeps the literal-insert semantics of <C-r><C-o>+ (no
--     auto-indent cascade, no abbreviation re-triggering).
local function clipboard_holds_image()
	local ok, proc = pcall(vim.system, { "wl-paste", "--list-types" }, { text = true })
	if not ok then
		return false -- no wl-paste (non-wayland session)
	end
	local res = proc:wait()
	return res.code == 0 and (res.stdout or ""):find("image/", 1, true) ~= nil
end

vim.keymap.set("i", "<C-v>", function()
	if vim.bo.filetype == "markdown" and clipboard_holds_image() then
		vim.cmd("stopinsert")
		-- schedule: let the mode change settle before the prompt opens
		vim.schedule(function()
			vim.cmd("ObsidianPasteImg")
		end)
		return
	end
	local text = vim.fn.getreg("+")
	if text == "" then
		return
	end
	local ok, proc = pcall(vim.system, { "iconv", "-f", "UTF-8", "-t", "UTF-8", "-c" }, { stdin = text })
	if ok then
		local res = proc:wait()
		if res.code == 0 and res.stdout and res.stdout ~= text then
			vim.notify(
				("paste: dropped %d invalid UTF-8 byte(s) from the clipboard (they crash harper-ls)"):format(
					#text - #res.stdout
				),
				vim.log.levels.WARN
			)
			text = res.stdout
		end
	end
	vim.api.nvim_paste(text, false, -1)
end, { silent = true, desc = "Paste from system clipboard (image-aware, UTF-8-scrubbed)" })
vim.keymap.set("c", "<C-v>", "<C-r><C-o>+", { noremap = true, desc = "Paste from system clipboard" })
vim.keymap.set("i", "<C-q>", "<C-v>", { noremap = true, desc = "Insert literal character (former <C-v>)" })

-- Paste the system clipboard below the current line, wrapped in a ``` fence.
-- <leader>p` leaves the cursor on the (blank) line just below the closing fence,
-- ready to keep writing; <leader>P` restores the original cursor position.
-- NOTE: this makes bare <leader>p (image paste) wait one 'timeoutlen'
-- to see whether a ` follows — the cost of hanging both off the p/P prefix.
local function paste_fenced_block(keep_cursor)
	local clip = vim.fn.getreg("+")
	if clip == "" then
		clip = vim.fn.getreg('"') -- fall back to the unnamed register
	end
	if clip == "" then
		vim.notify("Clipboard is empty", vim.log.levels.WARN)
		return
	end

	-- Split into lines, dropping a single trailing newline so we don't emit a
	-- blank line inside the fence.
	local content = vim.split((clip:gsub("\n$", "")), "\n", { plain = true })
	local block = { "```" }
	vim.list_extend(block, content)
	table.insert(block, "```")

	local orig = vim.api.nvim_win_get_cursor(0) -- {row(1-idx), col}
	local row = orig[1]
	vim.api.nvim_buf_set_lines(0, row, row, false, block) -- insert below current line

	if keep_cursor then
		vim.api.nvim_win_set_cursor(0, orig)
		return
	end

	-- Focus the line below the closing fence, creating it if we hit EOF.
	local target = row + #block + 1
	if target > vim.api.nvim_buf_line_count(0) then
		vim.api.nvim_buf_set_lines(0, -1, -1, false, { "" })
	end
	vim.api.nvim_win_set_cursor(0, { target, 0 })
end

vim.keymap.set("n", "<leader>p`", function()
	paste_fenced_block(false)
end, { silent = true, desc = "Paste clipboard as ``` fence (cursor below fence)" })
vim.keymap.set("n", "<leader>P`", function()
	paste_fenced_block(true)
end, { silent = true, desc = "Paste clipboard as ``` fence (cursor stays)" })
