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

map("n", "<leader>ch", "<cmd>NvCheatsheet<CR>", { desc = "Toggle NvCheatsheet" })

-- global lsp mappings
map("n", "<leader>lf", vim.diagnostic.open_float, { desc = "Lsp floating diagnostics" })
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Lsp prev diagnostic" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Lsp next diagnostic" })
map("n", "<leader>dl", vim.diagnostic.setloclist, { desc = "Lsp diagnostic loclist" })

-- tabufline
-- map("n", "<leader>b", "<cmd>enew<CR>", { desc = "Buffer New" })
-- map("n", "<leader>x", function()
--   require("nvchad.tabufline").close_buffer()
-- end, { desc = "Buffer Close" })

-- nvimtree
local snacks = require("snacks")
map("n", "<leader>e", function()
	snacks.explorer()
end, { desc = "Toggle Explorer" })

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
vim.api.nvim_set_keymap("n", "N", "Nzzzv", { noremap = true })
vim.api.nvim_set_keymap("n", "n", "nzzzv", { noremap = true })
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
map("v", "/", 'y<Esc>/<C-r>"', { noremap = true })
map("v", "<M-r>", ":'<,'>s/<C-r>\"", { noremap = true })

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

local betterTerm = require("betterTerm")
vim.keymap.set({ "n", "t" }, "<C-;>", betterTerm.open, { desc = "Open terminal" })

-- toggle firts term
-- Select term focus
vim.keymap.set({ "n" }, "<leader>tt", betterTerm.select, { desc = "Select terminal" })
-- Create new term
local current = 0
vim.keymap.set({ "n" }, "<leader>tn", function()
	betterTerm.open(current)
	current = current + 1
end, { desc = "New terminal" })
betterTerm.setup()

vim.keymap.set({ "i", "n", "t" }, "<C-k>", "<cmd>TmuxNavigateUp<CR>", { noremap = true, silent = true })
vim.keymap.set({ "i", "n", "t" }, "<C-j>", "<cmd>TmuxNavigateDown<CR>", { noremap = true, silent = true })
vim.keymap.set({ "i", "n", "t" }, "<C-h>", "<cmd>TmuxNavigateLeft<CR>", { noremap = true, silent = true })
vim.keymap.set({ "i", "n", "t" }, "<C-l>", "<cmd>TmuxNavigateRight<CR>", { noremap = true, silent = true })

-- vim.keymap.set("n", "<leader>ls", require("auto-session.session-lens").search_session, {
-- 	noremap = true,
-- })
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

vim.keymap.set("n", "<leader>c?", require("CopilotChat").toggle)

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
local function getCurrentWeekNumber()
	local current_date = os.date("*t")
	local week_number = os.date("%W", os.time(current_date))
	return tonumber(week_number) + 1
end
vim.keymap.set("n", "<leader>gl", "<cmd>ObsidianFollowLink<CR>i", { noremap = true })
vim.keymap.set("n", "<leader>od", "<cmd>ObsidianDailies<CR>", { noremap = true })
vim.keymap.set("n", "<leader>op", "<cmd>ObsidianPasteImg<CR>i", { noremap = true })

function PasteClipboardImage()
	-- Get the current timestamp
	local timestamp = os.date("%Y%m%d%H%M%S")

	-- Create the image file name
	local image_name = timestamp .. ".png"

	-- Get the current directory
	local current_dir = vim.fn.expand("%:p:h")

	-- Full path for the new image
	local image_path = current_dir .. "/" .. image_name

	-- Command to save clipboard image (assumes xclip for Linux)
	local save_command = string.format("wl-paste -t image/png > %s", image_path)

	-- Execute the save command
	local success = os.execute(save_command)

	if success then
		-- Create the markdown image link
		local markdown_link = string.format("![%s](./%s)", timestamp, image_name)

		-- Insert the markdown link at the cursor position
		vim.api.nvim_put({ markdown_link }, "c", true, true)

		print("Image saved and link inserted.")
	else
		print("Failed to save image from clipboard.")
	end
end

-- Map the function to a key combination (e.g., <leader>p)
vim.api.nvim_set_keymap("n", "<leader>p", ":lua PasteClipboardImage()<CR>", { noremap = true, silent = true })

local week_number = getCurrentWeekNumber()
local title = string.format("2025-W%d", week_number)

vim.keymap.set("n", "<leader>ow", function()
	vim.api.nvim_command(string.format(":ObsidianNewFromTemplate %s", "./notes/dailies/" .. title .. ".md"))
end, { noremap = true })

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
	vim.api.nvim_command(":save")
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

vim.api.nvim_set_keymap("n", "<leader>sc", ":lua require'sc-im'.open_in_scim()<CR>", { noremap = true, silent = true })
