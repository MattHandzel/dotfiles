-- Delete or archive "the file I'm on": the entry under the cursor in an oil
-- buffer, otherwise the current buffer's file. Archive moves the file to
-- <git root>/archive/<path relative to root>, preserving its subpath.
local M = {}

-- returns absolute path or nil
local function target_path()
	if vim.bo.filetype == "oil" then
		local oil = require("oil")
		local dir = oil.get_current_dir()
		local entry = oil.get_cursor_entry()
		if dir and entry and entry.name then
			return vim.fs.normalize(dir .. entry.name)
		end
		return nil
	end
	local name = vim.api.nvim_buf_get_name(0)
	if name == "" or name:match("^%w+://") then
		return nil
	end
	return vim.fs.normalize(name)
end

-- Name of the entry the cursor should land on once the current one is gone:
-- the next one down, else the one above. Call BEFORE the file is moved.
local function neighbor_entry_name()
	if vim.bo.filetype ~= "oil" then
		return nil
	end
	local oil = require("oil")
	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	for _, probe in ipairs({ lnum + 1, lnum - 1 }) do
		local ok, entry = pcall(oil.get_entry_on_line, 0, probe)
		if ok and entry and entry.name and entry.name ~= ".." then
			return entry.name
		end
	end
	return nil
end

-- oil's refresh is a `:edit!`, which parks the cursor at the top. Hand oil the
-- entry to seek so it restores position itself once the async render finishes.
local function refresh_oil(seek_name)
	if vim.bo.filetype ~= "oil" then
		return
	end
	if seek_name then
		pcall(function()
			require("oil.view").set_last_cursor(vim.api.nvim_buf_get_name(0), seek_name)
		end)
	end
	pcall(function()
		require("oil.actions").refresh.callback()
	end)
end

local function find_buf(path)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.fs.normalize(vim.api.nvim_buf_get_name(buf)) == path then
			return buf
		end
	end
end

local function wipe_buf(buf)
	local ok = pcall(require, "bufdelete")
	if ok then
		require("bufdelete").bufwipeout(buf, true)
	else
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

-- Move to the freedesktop trash (~/.local/share/Trash), never a permanent
-- delete. Prefers trash-cli; falls back to oil's own freedesktop trash
-- implementation. Both write .trashinfo, so `trash-restore` can undo it.
---@param path string
---@param cb fun(err?: string)
local function trash(path, cb)
	if vim.fn.executable("trash-put") == 1 then
		vim.system({ "trash-put", "--", path }, { text = true }, function(res)
			if res.code == 0 then
				cb()
				return
			end
			local msg = vim.trim(res.stderr or "")
			cb(msg ~= "" and msg or ("trash-put exited " .. res.code))
		end)
		return
	end
	local ok, freedesktop = pcall(require, "oil.adapters.trash.freedesktop")
	if ok and freedesktop.delete_to_trash then
		freedesktop.delete_to_trash(path, cb)
		return
	end
	cb("no trash backend available (install trash-cli)")
end

function M.delete()
	local path = target_path()
	if not path then
		vim.notify("No file to trash here", vim.log.levels.WARN)
		return
	end
	local is_dir = vim.fn.isdirectory(path) == 1
	local display = vim.fn.fnamemodify(path, ":~:.")
	local prompt = ("Move to trash: %s%s?"):format(display, is_dir and " (directory)" or "")
	if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
		return
	end
	local seek = neighbor_entry_name()
	trash(path, function(err)
		vim.schedule(function()
			if err then
				vim.notify("Failed to trash " .. display .. ": " .. err, vim.log.levels.ERROR)
				return
			end
			local buf = find_buf(path)
			if buf then
				wipe_buf(buf)
			end
			refresh_oil(seek)
			vim.notify("Trashed " .. display .. " (restore: trash-restore)", vim.log.levels.INFO)
		end)
	end)
end

function M.archive()
	local path = target_path()
	if not path then
		vim.notify("No file to archive here", vim.log.levels.WARN)
		return
	end
	local display = vim.fn.fnamemodify(path, ":~:.")

	local buf = find_buf(path)
	if buf and vim.bo[buf].modified then
		vim.notify(display .. " has unsaved changes — save before archiving", vim.log.levels.WARN)
		return
	end

	local root = vim.fs.root(path, ".git") or vim.uv.cwd()
	local rel
	if vim.startswith(path, root .. "/") then
		rel = path:sub(#root + 2)
	else
		rel = vim.fs.basename(path)
	end
	if rel == "archive" or vim.startswith(rel, "archive/") then
		vim.notify(display .. " is already under archive/", vim.log.levels.WARN)
		return
	end

	local dest = root .. "/archive/" .. rel
	if vim.uv.fs_stat(dest) then
		local stem, ext = dest:match("^(.+)(%.[^./]+)$")
		local suffix = "-" .. os.date("%Y%m%d-%H%M%S")
		dest = stem and (stem .. suffix .. ext) or (dest .. suffix)
	end

	local seek = neighbor_entry_name()
	vim.fn.mkdir(vim.fs.dirname(dest), "p")
	if vim.fn.rename(path, dest) ~= 0 then
		vim.notify("Failed to move " .. display .. " to " .. dest, vim.log.levels.ERROR)
		return
	end

	if buf then
		if buf == vim.api.nvim_get_current_buf() then
			vim.cmd.edit(vim.fn.fnameescape(dest))
		end
		wipe_buf(buf)
	end
	refresh_oil(seek)
	vim.notify("Archived → " .. vim.fn.fnamemodify(dest, ":~:."), vim.log.levels.INFO)
end

return M
