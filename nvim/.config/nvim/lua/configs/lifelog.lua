-- lifelog G2: which files Neovim opens, switches to and saves, one JSON line each.
--
-- kitty is the top app on the Mac and its window titles rarely name the file, so `lifelog at 14:32`
-- (~/Obsidian/Main/scripts/lifelog) couldn't say what was being edited. This log answers that; the
-- lifelog store copies it every 10 min. Paths and times only, never file contents.
--
-- Writes ~/.local/state/nvim-files/<local date>.jsonl: {"ts", "event": "open"|"enter"|"save", "path", "cwd"}.
-- Terminal buffers add {"event": "term", "path": "term://…", "pid": <the shell's pid>, "kids": [<its child pids>],
-- "title": <the terminal's title>} each time one gets focus: Matt's Claude Code sessions run in :terminal
-- buffers here, so lifelog's `claude-at` maps the claude child pid to its session (~/.claude/sessions/<pid>.json).
-- Spec: ~/Obsidian/Main/capture/spec-lifelog-bugs-checkoffs-sync-2026-10-06.md (D3, G2; Matt approved 2026-10-06).

local M = {}

local DIR = vim.env.NVIM_FILES_LOG or vim.fn.expand("~/.local/state/nvim-files")
local SAVE_EVERY = 60 -- seconds between two "save" lines for one file (configs/autosave.lua saves every 5 min)

local last_path = nil
local last_save = {}

local function stamp(now)
	local z = os.date("%z", now) -- "-0700"; lifelog's parser wants "-07:00"
	return os.date("%Y-%m-%dT%H:%M:%S", now) .. z:sub(1, 3) .. ":" .. z:sub(4)
end

local function write(event, path, extra)
	local now = os.time()
	local rec = { ts = stamp(now), event = event, path = path, cwd = vim.fn.getcwd() }
	for k, v in pairs(extra or {}) do
		rec[k] = v
	end
	local line = vim.json.encode(rec)
	vim.fn.mkdir(DIR, "p")
	local f = io.open(DIR .. "/" .. os.date("%Y-%m-%d", now) .. ".jsonl", "a")
	if f then
		f:write(line, "\n")
		f:close()
	end
end

-- A real file on disk: not a terminal, help page, file tree or scratch buffer.
local function file_of(buf)
	if vim.bo[buf].buftype ~= "" then
		return nil
	end
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" or name:match("^%w+://") then
		return nil
	end
	return vim.fn.fnamemodify(name, ":p")
end

local function on(event)
	return function(args)
		pcall(function() -- logging must never get in the way of editing
			local path = file_of(args.buf)
			if not path then
				return
			end
			if event == "save" then
				local now = os.time()
				if now - (last_save[path] or 0) < SAVE_EVERY then
					return
				end
				last_save[path] = now
			elseif path == last_path then
				return
			end
			if event ~= "save" then
				last_path = path
			end
			write(event, path)
		end)
	end
end

-- A terminal buffer got focus. Logged once per switch (BufEnter, WinEnter and TermEnter all fire on
-- one switch), and again when nvim regains focus from another app with a terminal in front.
local function on_term(force)
	return function(args)
		pcall(function()
			local buf = (args and args.buf and args.buf > 0) and args.buf or vim.api.nvim_get_current_buf()
			if buf ~= vim.api.nvim_get_current_buf() or vim.bo[buf].buftype ~= "terminal" then
				return
			end
			local path = vim.api.nvim_buf_get_name(buf)
			if path == last_path and not force then
				return
			end
			last_path = path
			local pid = vim.b[buf].terminal_job_pid
			local kids = {} -- children and grandchildren: claude may sit under a wrapper script
			for _, k in ipairs(pid and vim.api.nvim_get_proc_children(pid) or {}) do
				table.insert(kids, k)
				vim.list_extend(kids, vim.api.nvim_get_proc_children(k))
			end
			local title = vim.b[buf].term_title -- Claude Code sets it to "✳ <session title>"
			write("term", path, { pid = pid, kids = kids, title = title ~= path and title or nil })
		end)
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("LifelogFiles", { clear = true })
	vim.api.nvim_create_autocmd("BufReadPost", { group = group, callback = on("open") })
	vim.api.nvim_create_autocmd("BufEnter", { group = group, callback = on("enter") })
	vim.api.nvim_create_autocmd("BufWritePost", { group = group, callback = on("save") })
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TermEnter" }, { group = group, callback = on_term(false) })
	vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = on_term(true) })
end

return M
