local M = {}

M.ui = {
	theme = "chadracula-evondev",

	-- gdoc-sync state lives in the statusline, NOT in notifications. The plugin is
	-- configured with notify = "errors" (lua/plugins/init.lua), so a push/pull that
	-- works says nothing at all; this is where you check it when you want to.
	--
	-- Shows nothing unless the buffer is a linked Google Doc. Then:
	--   󰈙 gdoc              linked
	--   󰈙 gdoc (watching)   a watcher is live on it
	--   󰈙 gdoc CONFLICT     needs :Gdoc conflict / :Gdoc resolve
	statusline = {
		order = { "mode", "file", "git", "%=", "lsp_msg", "%=", "diagnostics", "lsp", "gdoc", "cwd", "cursor" },
		modules = {
			gdoc = function()
				-- package.loaded, not require: the plugin is lazy (ft/cmd), and a
				-- require() here would make every statusline redraw in every buffer
				-- force-load it.
				local gdoc = package.loaded["gdoc-sync"]
				if not gdoc then
					return ""
				end
				local ok, sl = pcall(require, "gdoc-sync.statusline")
				if not ok then
					return ""
				end
				local text = sl.component()
				if text == "" then
					return ""
				end
				local file = vim.api.nvim_buf_get_name(require("nvchad.stl.utils").stbufnr())
				if gdoc._conflicts and gdoc._conflicts[file] then
					return "%#St_LspError# " .. text .. " CONFLICT "
				end
				return "%#St_Lsp# " .. text .. " "
			end,
		},
	},
}

return M
