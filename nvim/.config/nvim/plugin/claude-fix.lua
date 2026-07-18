-- :ClaudeFix [extra notes]
-- Collect current errors/warnings (LSP diagnostics + :messages) plus referenced
-- source snippets, then launch a Claude agent in a terminal split with that
-- bundled context as the opening prompt.

local function get_messages(max_lines)
	max_lines = max_lines or 300
	local ok, out = pcall(vim.api.nvim_exec2, "messages", { output = true })
	if not ok or type(out) ~= "table" or type(out.output) ~= "string" or out.output == "" then
		return ""
	end
	local lines = vim.split(out.output, "\n", { plain = true })
	while #lines > 0 and lines[1]:match("^%s*$") do
		table.remove(lines, 1)
	end
	if #lines > max_lines then
		lines = vim.list_slice(lines, #lines - max_lines + 1)
	end
	return table.concat(lines, "\n")
end

local function get_diagnostics()
	local sev = { [1] = "ERROR", [2] = "WARN", [3] = "INFO", [4] = "HINT" }
	local diags = vim.diagnostic.get(nil)
	if #diags == 0 then
		return ""
	end
	local lines = {}
	for _, d in ipairs(diags) do
		local fname = vim.api.nvim_buf_get_name(d.bufnr or 0)
		if fname == "" then
			fname = "[buf " .. tostring(d.bufnr or "?") .. "]"
		end
		table.insert(
			lines,
			string.format(
				"[%s] %s:%d:%d  %s%s",
				sev[d.severity] or "?",
				fname,
				(d.lnum or 0) + 1,
				(d.col or 0) + 1,
				(d.message or ""):gsub("\n", " "),
				d.source and (" (" .. d.source .. ")") or ""
			)
		)
	end
	return table.concat(lines, "\n")
end

local function get_notifications(max_items)
	max_items = max_items or 40
	if type(_G.Snacks) ~= "table" then
		return ""
	end
	local notifier = _G.Snacks.notifier
	if type(notifier) ~= "table" or type(notifier.get_history) ~= "function" then
		return ""
	end
	local ok, hist = pcall(notifier.get_history, { sort = { "added" } })
	if not ok or type(hist) ~= "table" or #hist == 0 then
		return ""
	end
	-- get_history sorts ascending by `added`; keep the most recent tail
	if #hist > max_items then
		hist = vim.list_slice(hist, #hist - max_items + 1)
	end
	local lines = {}
	for _, n in ipairs(hist) do
		local lvl = tostring(n.level or "info"):upper()
		local title = (n.title and n.title ~= "") and ("[" .. n.title .. "] ") or ""
		local msg = tostring(n.msg or ""):gsub("%s+$", "")
		table.insert(lines, string.format("[%s] %s%s", lvl, title, msg))
	end
	return table.concat(lines, "\n")
end

-- Resolve a representative editable config file to its real (symlink-followed)
-- location. Returns realpath, the relative probe used, or nil.
local function resolve_config_source()
	local cfg = vim.fn.stdpath("config")
	for _, rel in ipairs({ "/lua/mappings.lua", "/lua/options.lua", "/lua/plugins/init.lua" }) do
		local rp = vim.uv and vim.uv.fs_realpath(cfg .. rel)
		if rp then
			return rp, rel
		end
	end
	return nil
end

local function get_environment()
	local lines = {}
	local v = vim.version()
	local ver = string.format("%d.%d.%d", v.major or 0, v.minor or 0, v.patch or 0)
	if v.prerelease then
		ver = ver .. " (prerelease/nightly)"
	end
	table.insert(lines, "Neovim: " .. ver)
	for _, name in ipairs({ "config", "data", "state", "cache" }) do
		table.insert(lines, name .. ": " .. vim.fn.stdpath(name))
	end

	local cfg = vim.fn.stdpath("config")
	local init_real = vim.uv and vim.uv.fs_realpath(cfg .. "/init.lua")
	if init_real and init_real ~= cfg .. "/init.lua" then
		table.insert(lines, "init.lua resolves to: " .. init_real)
		if init_real:find("/nix/store/", 1, true) then
			table.insert(
				lines,
				"NOTE: init.lua is Nix-generated and READ-ONLY (/nix/store). Fix Nix-generated files in the NixOS / home-manager config, never in place."
			)
		end
	end

	local real, rel = resolve_config_source()
	if real and rel and real ~= cfg .. rel then
		local source_root = real:sub(1, #real - #rel)
		table.insert(
			lines,
			"editable config sources live in: "
				.. source_root
				.. "  (edit the real files there — they are symlinked into "
				.. cfg
				.. ")"
		)
	end

	return table.concat(lines, "\n")
end

local function get_git_context()
	local real, rel = resolve_config_source()
	if not real or not rel then
		return ""
	end
	local dir = real:sub(1, #real - #rel) -- real config dir inside the dotfiles repo

	local function git(args)
		local cmd = vim.list_extend({ "git", "-C", dir }, args)
		local ok, res = pcall(function()
			return vim.system(cmd, { text = true }):wait()
		end)
		if not ok or type(res) ~= "table" or res.code ~= 0 then
			return nil
		end
		return vim.trim(res.stdout or "")
	end

	local root = git({ "rev-parse", "--show-toplevel" })
	if not root then
		return ""
	end

	local lines = {}
	local branch = git({ "rev-parse", "--abbrev-ref", "HEAD" })
	table.insert(lines, "repo: " .. root .. (branch and ("  branch: " .. branch) or ""))
	-- pathspec "." is relative to `dir`, so log/diff stay scoped to the nvim config
	local log = git({ "log", "--oneline", "-8", "--", "." })
	if log and log ~= "" then
		table.insert(lines, "recent commits touching the nvim config:")
		table.insert(lines, log)
	end
	local stat = git({ "diff", "--stat", "--", "." })
	if stat and stat ~= "" then
		table.insert(lines, "uncommitted changes in the nvim config:")
		table.insert(lines, stat)
	end
	local untracked = git({ "ls-files", "--others", "--exclude-standard", "--", "." })
	if untracked and untracked ~= "" then
		table.insert(lines, "untracked files in the nvim config:")
		table.insert(lines, untracked)
	end
	return table.concat(lines, "\n")
end

local function get_lsp_clients()
	local get = vim.lsp.get_clients or vim.lsp.get_active_clients
	if type(get) ~= "function" then
		return ""
	end
	local ok, clients = pcall(get)
	if not ok or type(clients) ~= "table" or #clients == 0 then
		return ""
	end
	local lines = {}
	for _, c in ipairs(clients) do
		local bufs = 0
		for _ in pairs(c.attached_buffers or {}) do
			bufs = bufs + 1
		end
		table.insert(
			lines,
			string.format("%s  (id %s, %d buffer%s attached)", c.name, tostring(c.id), bufs, bufs == 1 and "" or "s")
		)
	end
	return table.concat(lines, "\n")
end

local function extract_refs(text)
	local refs, seen = {}, {}
	for path, line in text:gmatch("(/[%w%./_%-]+):(%d+)") do
		local key = path .. ":" .. line
		if not seen[key] and vim.fn.filereadable(path) == 1 then
			seen[key] = true
			table.insert(refs, { path = path, line = tonumber(line) })
			if #refs >= 15 then
				break
			end
		end
	end
	return refs
end

local function read_snippet(path, line, ctx)
	ctx = ctx or 6
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok or type(lines) ~= "table" or #lines == 0 then
		return nil
	end
	local start = math.max(1, line - ctx)
	local stop = math.min(#lines, line + ctx)
	local out = {}
	for i = start, stop do
		local marker = (i == line) and ">>" or "  "
		table.insert(out, string.format("%s %5d  %s", marker, i, lines[i] or ""))
	end
	return table.concat(out, "\n")
end

-- First `max_words` words of the current buffer, marked as a partial snippet.
-- Returns text, truncated(bool), total_lines, shown_lines — or nil if N/A.
local function get_buffer_snippet(max_words)
	max_words = max_words or 1000
	local buf = vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= "" then
		return nil
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	if #lines == 0 or (#lines == 1 and lines[1] == "") then
		return nil
	end
	local out, words, truncated = {}, 0, false
	for _, line in ipairs(lines) do
		local _, n = line:gsub("%S+", "")
		if words + n > max_words and #out > 0 then
			truncated = true
			break
		end
		words = words + n
		table.insert(out, line)
	end
	return table.concat(out, "\n"), truncated, #lines, #out
end

local function build_prompt(extra)
	local messages = get_messages(300)
	local diagnostics = get_diagnostics()
	local notifications = get_notifications(40)
	local environment = get_environment()
	local lsp_clients = get_lsp_clients()
	local git_context = get_git_context()
	local cwd = (vim.uv and vim.uv.cwd()) or vim.fn.getcwd()
	local cur = vim.api.nvim_buf_get_name(0)
	local cur_line = vim.api.nvim_win_get_cursor(0)[1]
	local buf_snippet, buf_truncated, buf_total, buf_shown = get_buffer_snippet(1000)

	local out = {}
	table.insert(
		out,
		"I hit errors/warnings inside Neovim. Diagnose the root cause and fix the relevant files."
	)
	table.insert(
		out,
		"If the root cause is a corrupted state/cache file under stdpath('data') or stdpath('state'), it is safe to repair or delete it — but explain why before doing so."
	)
	table.insert(out, "")
	table.insert(out, "cwd: " .. cwd)
	if cur ~= "" then
		table.insert(out, "current buffer: " .. cur .. ":" .. cur_line)
	end
	if extra and extra ~= "" then
		table.insert(out, "")
		table.insert(out, "Additional notes: " .. extra)
	end
	table.insert(out, "")

	if environment ~= "" then
		table.insert(out, "== Environment ==")
		table.insert(out, environment)
		table.insert(out, "")
	end

	if buf_snippet then
		table.insert(
			out,
			string.format(
				"== Current buffer SNIPPET: %s (PARTIAL — first ~1000 words, lines 1-%d of %d; read the file for the rest) ==",
				cur ~= "" and cur or "[unnamed buffer]",
				buf_shown,
				buf_total
			)
		)
		table.insert(out, buf_snippet)
		if buf_truncated then
			table.insert(out, "... [snippet truncated — buffer continues beyond this point]")
		end
		table.insert(out, "")
	end

	if diagnostics ~= "" then
		table.insert(out, "== LSP diagnostics ==")
		table.insert(out, diagnostics)
		table.insert(out, "")
	end

	if lsp_clients ~= "" then
		table.insert(out, "== Active LSP clients ==")
		table.insert(out, lsp_clients)
		table.insert(out, "")
	end

	if notifications ~= "" then
		table.insert(out, "== Recent notifications (vim.notify / snacks) ==")
		table.insert(out, notifications)
		table.insert(out, "")
	end

	if messages ~= "" then
		table.insert(out, "== :messages (most recent) ==")
		table.insert(out, messages)
		table.insert(out, "")
	end

	local combined = table.concat({ messages, diagnostics, notifications }, "\n")
	local refs = extract_refs(combined)
	if #refs > 0 then
		table.insert(out, "== Referenced source snippets ==")
		for _, r in ipairs(refs) do
			local s = read_snippet(r.path, r.line, 6)
			if s then
				table.insert(out, "-- " .. r.path .. " (line " .. r.line .. ") --")
				table.insert(out, s)
				table.insert(out, "")
			end
		end
	end

	if git_context ~= "" then
		table.insert(out, "== Recent config git activity (likely-culprit recent changes) ==")
		table.insert(out, git_context)
		table.insert(out, "")
	end

	local empty = (messages == "" and diagnostics == "" and notifications == "")
	return table.concat(out, "\n"), empty
end

local function resolve_claude()
	local p = vim.fn.exepath("claude")
	if p ~= "" then
		return p
	end
	local home = vim.env.HOME or ""
	for _, c in ipairs({
		home .. "/.npm-packages/bin/claude",
		home .. "/.local/bin/claude",
		home .. "/.bun/install/global/bin/claude",
		home .. "/.nix-profile/bin/claude",
		"/run/current-system/sw/bin/claude",
		"/usr/local/bin/claude",
	}) do
		if vim.fn.executable(c) == 1 then
			return c
		end
	end
	return nil
end

local function start_terminal(cmd_list)
	vim.cmd("botright 20split | enew")
	local job_opts = {
		term = true,
		on_exit = function(_, code)
			if code ~= 0 then
				vim.schedule(function()
					vim.notify("ClaudeFix: process exited with code " .. tostring(code), vim.log.levels.WARN)
				end)
			end
		end,
	}
	local jid
	if vim.fn.has("nvim-0.10") == 1 then
		local ok, res = pcall(vim.fn.jobstart, cmd_list, job_opts)
		jid = ok and res or -1
		if jid <= 0 and vim.fn.exists("*termopen") == 1 then
			jid = vim.fn.termopen(cmd_list, { on_exit = job_opts.on_exit })
		end
	else
		jid = vim.fn.termopen(cmd_list, { on_exit = job_opts.on_exit })
	end
	if not jid or jid <= 0 then
		vim.notify(
			"ClaudeFix: failed to spawn terminal (jid=" .. tostring(jid) .. ") cmd=" .. vim.inspect(cmd_list),
			vim.log.levels.ERROR
		)
		return false
	end
	vim.cmd("startinsert")
	return true
end

vim.api.nvim_create_user_command("ClaudeFix", function(opts)
	local prompt, empty = build_prompt(opts.args)
	if empty then
		vim.notify("ClaudeFix: no diagnostics or :messages content found", vim.log.levels.WARN)
		return
	end

	local claude = resolve_claude()
	if not claude then
		vim.notify(
			"ClaudeFix: 'claude' binary not found in PATH (a shell alias is not enough). Install Claude Code or add its bin dir to PATH.",
			vim.log.levels.ERROR
		)
		return
	end

	local tmp = vim.fn.tempname() .. "-claude-fix.md"
	pcall(vim.fn.writefile, vim.split(prompt, "\n", { plain = true }), tmp)

	if start_terminal({ claude, "--dangerously-skip-permissions", prompt }) then
		vim.notify("ClaudeFix: launched " .. claude .. " (prompt saved to " .. tmp .. ")", vim.log.levels.INFO)
	end
end, { nargs = "?", desc = "Launch Claude agent to fix current errors/warnings" })
