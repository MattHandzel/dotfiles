-- Timed autosave.
--
-- Replaces pocco81/auto-save.nvim, whose configuration was silently inert.
-- That plugin's plugin/auto-save.lua calls require("auto-save").on() at
-- plugin-load time, BEFORE lazy runs the spec's config() -> setup(). on()
-- reads trigger_events at registration time, so the autocmds were always
-- built from the DEFAULTS ({"InsertLeave", "TextChanged"}); our
-- trigger_events = {} landed in the config table afterwards and was never
-- read again. Likewise `debounce_delay` is captured into a local `save_func`
-- at module-require time, so our 300000 never reached the debounce either --
-- it stayed at the default 135ms. Verified live: the config table read back
-- as trigger_events = {} / debounce_delay = 300000 while the registered
-- autocmds were still InsertLeave + TextChanged.
--
-- Net effect: every insert-leave wrote the buffer, which fires BufWritePre,
-- which runs conform (prettier on markdown) -- so prose was being reflowed
-- mid-thought. Upstream also echoes its "saved at" message twice, which is
-- why :messages showed every timestamp in pairs.
--
-- This module drives saves from a single 5-minute timer instead. Formatting
-- on write is deliberately kept -- the fix is that it now happens on a
-- predictable cadence rather than on every insert-leave.

local M = {}

local INTERVAL_MS = 5 * 60 * 1000
local AUGROUP = "TimedAutoSave"

-- The timer handle lives on a global rather than a module local because
-- :ReloadConfig (configs/reload.lua) wipes package.loaded and re-requires
-- this file. Without a handle that survives that, each reload would leave
-- another timer running and saves would multiply silently.
if _G.__timed_autosave_timer then
	pcall(function()
		_G.__timed_autosave_timer:stop()
		_G.__timed_autosave_timer:close()
	end)
	_G.__timed_autosave_timer = nil
end

if vim.g.timed_autosave_enabled == nil then
	vim.g.timed_autosave_enabled = true
end

-- Set when the timer fires while the user is mid-insert. The save is handed
-- to the next InsertLeave instead of being dropped, so a 5-minute tick that
-- lands mid-sentence still gets written -- just not under the cursor.
local pending = false

local function saveable(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return false
	end
	if not vim.bo[buf].modified or not vim.bo[buf].modifiable or vim.bo[buf].readonly then
		return false
	end
	-- Anything with a buftype is a terminal/quickfix/help/prompt scratch
	-- surface, not a file. Mirrors the BufWritePre guard in autocommands.lua.
	if vim.bo[buf].buftype ~= "" then
		return false
	end
	if vim.b[buf].large_file_mode then
		return false
	end
	return vim.api.nvim_buf_get_name(buf) ~= ""
end

local function write(buf)
	return pcall(vim.api.nvim_buf_call, buf, function()
		vim.cmd("silent! write")
	end)
end

--- Write one buffer if it is a modified file buffer. Returns true if written.
--- For close/quit paths: a 5-minute timer means a buffer is routinely still
--- dirty when you close it, and every close path in Neovim checks 'modified'
--- before any autocmd we could hook.
function M.save_buf(buf)
	if not vim.g.timed_autosave_enabled or not saveable(buf) then
		return false
	end
	local view = vim.fn.winsaveview()
	local ok = write(buf)
	pcall(vim.fn.winrestview, view)
	return ok
end

--- Write every modified file buffer. Returns the number written.
function M.save()
	local saved = 0
	-- Formatting can shift text above the cursor, so restore the viewport of
	-- the window we are actually looking at.
	local view = vim.fn.winsaveview()

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if saveable(buf) and write(buf) then
			saved = saved + 1
		end
	end

	pcall(vim.fn.winrestview, view)

	if saved > 0 then
		-- nvim_echo, not vim.notify: this should land in :messages without
		-- throwing a snacks toast every five minutes.
		vim.api.nvim_echo({
			{ ("AutoSave: saved %d file%s at %s"):format(saved, saved == 1 and "" or "s", vim.fn.strftime("%H:%M:%S")), "MsgArea" },
		}, true, {})
	end

	return saved
end

local function in_insert()
	local mode = vim.api.nvim_get_mode().mode
	return mode:find("^i") ~= nil or mode:find("^R") ~= nil or mode:find("^s") ~= nil
end

local function tick()
	if not vim.g.timed_autosave_enabled then
		return
	end
	if in_insert() then
		pending = true
		return
	end
	M.save()
end

local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })

vim.api.nvim_create_autocmd("InsertLeave", {
	group = group,
	pattern = "*",
	callback = function()
		if pending and vim.g.timed_autosave_enabled then
			pending = false
			M.save()
		end
	end,
})

-- Save before :q / :qa / :wq / ZZ decide whether they are allowed. VimLeavePre
-- (below) alone was too late: it only fires once the quit has already passed
-- the modified-buffer check, so a buffer edited in the last five minutes made
-- :q fail with "E37: No write since last change" and :qa with E162. QuitPre
-- and ExitPre both run before that check.
vim.api.nvim_create_autocmd("QuitPre", {
	group = group,
	pattern = "*",
	callback = function(ev)
		M.save_buf(ev.buf)
	end,
})

vim.api.nvim_create_autocmd("ExitPre", {
	group = group,
	pattern = "*",
	callback = function()
		if vim.g.timed_autosave_enabled then
			M.save()
		end
	end,
})

-- Never lose work to a quit, regardless of where the timer happens to be.
-- Still needed for exits that skip QuitPre/ExitPre (:qa!, :cq, signals).
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = group,
	pattern = "*",
	callback = function()
		if vim.g.timed_autosave_enabled then
			M.save()
		end
	end,
})

-- The tabline's close button (NvChad TbKillBuf -> tabufline.close_buffer) runs
-- `confirm bd<N>`. On a dirty buffer that raises a "Save changes?" prompt in a
-- noice popup; clicking the button again or pressing <Esc> cancels it, and
-- NvChad lets the resulting "E516: No buffers were deleted" escape with a full
-- Lua stack trace. Save first so the prompt never comes up. A cancel that
-- still happens (unnamed scratch buffer) is a choice, not an error.
--
-- The original is kept on the module table: :ReloadConfig re-requires this
-- file but not nvchad.tabufline, so without it every reload would wrap the
-- previous wrapper.
local tb_ok, tabufline = pcall(require, "nvchad.tabufline")
if tb_ok then
	tabufline.__close_buffer_orig = tabufline.__close_buffer_orig or tabufline.close_buffer
	tabufline.close_buffer = function(bufnr)
		bufnr = (bufnr and bufnr ~= 0) and bufnr or vim.api.nvim_get_current_buf()
		M.save_buf(bufnr)
		local ok, err = pcall(tabufline.__close_buffer_orig, bufnr)
		if not ok and not tostring(err):find("E516") then
			vim.notify(tostring(err), vim.log.levels.ERROR)
		end
	end
end

local timer = vim.uv.new_timer()
_G.__timed_autosave_timer = timer
timer:start(INTERVAL_MS, INTERVAL_MS, function()
	vim.schedule(tick)
end)

-- Kept under the old name so existing muscle memory still works.
vim.api.nvim_create_user_command("ASToggle", function()
	vim.g.timed_autosave_enabled = not vim.g.timed_autosave_enabled
	vim.notify("Timed autosave " .. (vim.g.timed_autosave_enabled and "on" or "off"), vim.log.levels.INFO)
end, { desc = "Toggle the 5-minute autosave" })

vim.api.nvim_create_user_command("ASSave", function()
	local n = M.save()
	if n == 0 then
		vim.notify("AutoSave: nothing modified", vim.log.levels.INFO)
	end
end, { desc = "Run the autosave write now" })

return M
