-- built-for-you: log a use line when Matt presses a key Claude built for him, for the keys under watch only.
--
-- The use check (~/Obsidian/Main/scripts/built-for-you/usecheck.py) writes the watch list each night to
-- ~/.local/state/built-for-you/watch-nvim.json: [{"id": "nvim-key:leader-ok", "lhs": "<leader>ok", "mode": "x"}, ...]
-- (mode "cmd" = an Ex command name, e.g. {"lhs": "KmsCapture", "mode": "cmd"}). Only those mappings are wrapped:
-- the wrapper appends one line to ~/.local/state/built-for-you/use-<date>.jsonl, the same shape as
-- registry.log_use() ({"ts", "id", "src", "what"}), then runs the original rhs or callback. Unwatched keys are
-- untouched, and an empty list installs nothing. Keys and times only, never buffer text.
--
-- lazy.nvim `keys` specs start as stubs that lazy deletes and replaces with the real mapping on first press, so a
-- wrapped stub logs that first press and the real mapping is re-wrapped right after (and on every User LazyLoad).
-- Spec: ~/Obsidian/Main/projects/built-for-you/built-for-you.md ("Detectors").

local M = {}

local STATE = vim.fn.expand("~/.local/state/built-for-you")
local WATCH = STATE .. "/watch-nvim.json"

local watch = {} -- list of {id, lhs, mode}
local ours = {} -- wrapper function -> true, so a re-wrap never wraps a wrapper
local last = {} -- id -> os.time() of the last line (one line per second per key at most)

local function stamp(now)
	local z = os.date("%z", now) -- "-0500"; registry.read_use_log wants ISO "-05:00"
	return os.date("%Y-%m-%dT%H:%M:%S", now) .. z:sub(1, 3) .. ":" .. z:sub(4)
end

local function log_use(id, what)
	local now = os.time()
	if last[id] == now then
		return
	end
	last[id] = now
	vim.fn.mkdir(STATE, "p")
	local f = io.open(STATE .. "/use-" .. os.date("%Y-%m-%d", now) .. ".jsonl", "a")
	if f then
		f:write(vim.json.encode({ ts = stamp(now), id = id, src = "nvim-key", what = what }), "\n")
		f:close()
	end
end

local function read_watch()
	local ok, lines = pcall(vim.fn.readfile, WATCH)
	if not ok or #lines == 0 then
		return {}
	end
	local ok2, list = pcall(vim.json.decode, table.concat(lines, "\n"))
	return (ok2 and type(list) == "table") and list or {}
end

local function wrap(w)
	local m = vim.fn.maparg(w.lhs, w.mode, false, true)
	if vim.tbl_isempty(m) or m.buffer == 1 or (m.callback and ours[m.callback]) then
		return
	end
	local fn
	if m.callback then
		local cb = m.callback
		fn = function(...)
			log_use(w.id, w.lhs)
			vim.schedule(M.rewrap)
			return cb(...)
		end
	else
		-- A string rhs runs as an expr mapping that returns it, so ":Cmd<CR>" in visual mode keeps its '<,'> range.
		local rhs = m.rhs or ""
		local was_expr = m.expr == 1
		fn = function()
			log_use(w.id, w.lhs)
			vim.schedule(M.rewrap)
			return was_expr and vim.api.nvim_eval(rhs) or rhs
		end
	end
	ours[fn] = true
	vim.keymap.set(w.mode, w.lhs, fn, {
		expr = (m.callback and m.expr == 1) or not m.callback,
		replace_keycodes = not m.callback or m.replace_keycodes == 1,
		noremap = m.noremap == 1,
		silent = m.silent == 1,
		nowait = m.nowait == 1,
		desc = m.desc,
	})
end

function M.rewrap()
	for _, w in ipairs(watch) do
		if w.mode ~= "cmd" then
			pcall(wrap, w)
		end
	end
end

function M.setup()
	watch = read_watch()
	if #watch == 0 then
		return
	end
	M.rewrap()
	local group = vim.api.nvim_create_augroup("bfy_keys", { clear = true })
	vim.api.nvim_create_autocmd("User", { group = group, pattern = "LazyLoad", callback = function()
		vim.schedule(M.rewrap)
	end })
	local cmds = {}
	for _, w in ipairs(watch) do
		if w.mode == "cmd" then
			cmds[w.lhs] = w.id
		end
	end
	if next(cmds) then
		vim.api.nvim_create_autocmd("CmdlineLeave", { group = group, pattern = ":", callback = function()
			if vim.v.event.abort then
				return
			end
			-- the command name after any range: "'<,'>KmsCapture" -> "KmsCapture"
			local name = vim.fn.getcmdline():match("^[%s%d%.,;:'<>%$%%+%-]*(%a%w*)")
			if name and cmds[name] then
				log_use(cmds[name], ":" .. name)
			end
		end })
	end
end

return M
