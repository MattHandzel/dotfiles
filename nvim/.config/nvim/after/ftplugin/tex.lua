-- <CR> follows the reference under the cursor, the way it follows links in
-- markdown (after/ftplugin/markdown.lua): \input / \include / \subfile /
-- \includegraphics open the file in this window, \href / \url open in the
-- browser. Nothing to follow: <CR> moves to the next line, as before.

local tex_buf = vim.api.nvim_get_current_buf()

local FILE_CMDS = { input = true, include = true, subfile = true, includegraphics = true, InputIfFileExists = true }
local URL_CMDS = { href = true, url = true }

-- Every \cmd[opts]{arg} on the line, with the 1-based column span it covers.
local function refs_on(line)
	local refs = {}
	local init = 1
	while true do
		local s, after, cmd = line:find("\\(%a+)", init)
		if not s then
			return refs
		end
		init = after + 1
		if FILE_CMDS[cmd] or URL_CMDS[cmd] then
			-- skip `*`, whitespace and an optional [opts] before the {arg}
			local p = line:match("^%*?%s*()", after + 1)
			if line:sub(p, p) == "[" then
				local _, close = line:find("%b[]", p)
				p = close and line:match("^%s*()", close + 1) or p
			end
			local _, e, arg = line:find("^{([^}]*)}", p)
			if e then
				refs[#refs + 1] = { s = s, e = e, cmd = cmd, arg = vim.trim(arg) }
				init = e + 1
			end
		end
	end
end

-- TeX resolves \input against the directory it was run from (the main file's),
-- not the including file's, so try vimtex's project root first.
local function resolve(arg, cmd)
	local dirs = {}
	local vt = vim.b[tex_buf].vimtex
	if vt and vt.root then
		dirs[#dirs + 1] = vt.root
	end
	dirs[#dirs + 1] = vim.fn.expand("%:p:h")
	dirs[#dirs + 1] = vim.fn.getcwd()
	-- TeX tries `<arg>.tex` before `<arg>` even when arg has a dot in it
	-- (\input{../sections/projects/taskwarrior.nvim}).
	local exts = cmd == "includegraphics" and { "", ".pdf", ".png", ".jpg", ".jpeg", ".eps" } or { ".tex", "" }
	for _, dir in ipairs(dirs) do
		for _, ext in ipairs(exts) do
			local path = vim.fs.normalize(vim.fs.joinpath(dir, arg .. ext))
			if vim.uv.fs_stat(path) then
				return path
			end
		end
	end
end

local function go_to()
	local line = vim.api.nvim_get_current_line()
	local col = vim.api.nvim_win_get_cursor(0)[2] + 1
	local refs = refs_on(line)
	local ref
	for _, r in ipairs(refs) do
		if col >= r.s and col <= r.e then
			ref = r
			break
		end
	end
	-- Cursor elsewhere on a line with exactly one reference (the usual
	-- `\input{...}` line): follow that one.
	ref = ref or (#refs == 1 and refs[1]) or nil
	if not ref or ref.arg == "" then
		return false
	end
	if URL_CMDS[ref.cmd] then
		vim.ui.open(ref.arg)
		return true
	end
	local path = resolve(ref.arg, ref.cmd)
	if not path then
		vim.notify("No file for \\" .. ref.cmd .. "{" .. ref.arg .. "}", vim.log.levels.WARN)
		return true
	end
	if ref.cmd == "includegraphics" and not path:match("%.tex$") then
		vim.ui.open(path)
	else
		vim.cmd.edit(vim.fn.fnameescape(path))
	end
	return true
end

vim.keymap.set("n", "<CR>", function()
	if not go_to() then
		vim.cmd("normal! j^")
	end
end, { buffer = tex_buf, silent = true, desc = "Go to \\input/\\include/link under cursor" })
