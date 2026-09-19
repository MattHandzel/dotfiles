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

--- Write every modified file buffer. Returns the number written.
function M.save()
	local saved = 0
	-- Formatting can shift text above the cursor, so restore the viewport of
	-- the window we are actually looking at.
	local view = vim.fn.winsaveview()

	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if saveable(buf) then
			local ok = pcall(vim.api.nvim_buf_call, buf, function()
				vim.cmd("silent! write")
			end)
			if ok then
				saved = saved + 1
			end
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

-- Never lose work to a quit, regardless of where the timer happens to be.
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = group,
	pattern = "*",
	callback = function()
		if vim.g.timed_autosave_enabled then
			M.save()
		end
	end,
})

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
