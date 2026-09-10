-- Drafting-velocity tracking for the waybar "custom/writing" widget.
-- Commands: :WriteFast, :WriteFastStop, :WriteFastReport
--
-- Global by design: you start a session once (here, or from Vicinae, or from
-- the shell) and then ANY prose buffer you type in joins it automatically. You
-- never name a file. Publishing the live buffer count is what makes this work
-- at all — the CLI otherwise only sees words at :w, which in a fast drafting
-- session is exactly when you are not looking at the widget.
--
-- Nothing is published unless a session is running, so this costs one cheap
-- file check (cached) per burst of typing and nothing else.

local PROSE = {
  markdown = true, text = true, org = true, rst = true,
  tex = true, plaintex = true, asciidoc = true, norg = true, vimwiki = true,
}

local DEBOUNCE_MS = 2000
local SESSION_CACHE_MS = 2000

local timers = {}
local session_checked_at, session_is_active = 0, false

-- Prefer the installed command. The fallback keeps this working in the window
-- between editing the flake and running `rebuild` — without it, :WriteFast
-- dies with a raw ENOENT stack trace from vim.system.
local function cli()
  if vim.fn.executable("writing-session") == 1 then
    return { "writing-session" }
  end
  local repo = vim.fn.expand(
    "~/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/writing-session.py")
  if vim.fn.filereadable(repo) == 1 and vim.fn.executable("python3") == 1 then
    return { "python3", repo }
  end
  return nil
end

local function run(args, on_done)
  local base = cli()
  if not base then
    vim.notify("writing-session not found — run `rebuild` to install it",
      vim.log.levels.ERROR)
    return
  end
  local cmd = vim.list_extend(vim.deepcopy(base), args)
  if on_done then
    vim.system(cmd, { text = true }, vim.schedule_wrap(on_done))
  else
    vim.system(cmd, { text = true })
  end
end

local function session_file()
  local base = vim.env.XDG_STATE_HOME
  if base == nil or base == "" then
    base = vim.fn.expand("~/.local/state")
  end
  return base .. "/writing-session/session.json"
end

local function session_active()
  local now = vim.uv.now()
  if now - session_checked_at > SESSION_CACHE_MS then
    session_is_active = vim.fn.filereadable(session_file()) == 1
    session_checked_at = now
  end
  return session_is_active
end

-- Must match count_words() in writing-session.py: YAML frontmatter is metadata,
-- not drafting. A mismatch here would make the count jump at every save.
local function buffer_words(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start = 1
  if lines[1] and lines[1]:match("^%-%-%-%s*$") then
    for i = 2, #lines do
      if lines[i]:match("^%-%-%-%s*$") then
        start = i + 1
        break
      end
    end
  end

  local count = 0
  for i = start, #lines do
    for _ in lines[i]:gmatch("%S+") do
      count = count + 1
    end
  end
  return count
end

local function publish(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return
  end
  run({ "live-update", path, tostring(buffer_words(bufnr)) })
end

local function schedule_publish(bufnr)
  if timers[bufnr] then
    timers[bufnr]:stop()
  else
    timers[bufnr] = vim.uv.new_timer()
  end
  timers[bufnr]:start(DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    publish(bufnr)
  end))
end

local function stop_timers()
  for _, timer in pairs(timers) do
    timer:stop()
  end
  timers = {}
end

-- One global autocmd; the session check gates it, so no per-buffer setup.
vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
  group = vim.api.nvim_create_augroup("WriteFast", { clear = true }),
  callback = function(ev)
    if not PROSE[vim.bo[ev.buf].filetype] then
      return
    end
    if vim.api.nvim_buf_get_name(ev.buf) == "" or not session_active() then
      return
    end
    schedule_publish(ev.buf)
  end,
})

vim.api.nvim_create_user_command("WriteFast", function()
  run({ "start" }, function(res)
    local out = ((res.code == 0 and res.stdout or res.stderr) or ""):gsub("%s+$", "")
    vim.notify(out ~= "" and out or "Writing session started",
      res.code == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
    session_checked_at = 0 -- re-check immediately so typing starts counting
    -- Seed the current buffer so its pre-session length becomes the baseline
    -- rather than being counted as words you just wrote.
    local buf = vim.api.nvim_get_current_buf()
    if res.code == 0 and PROSE[vim.bo[buf].filetype] then
      publish(buf)
    end
  end)
end, { desc = "Start a global writing session (waybar WPM widget)" })

vim.api.nvim_create_user_command("WriteFastStop", function()
  run({ "stop" }, function(res)
    local out = ((res.code == 0 and res.stdout or res.stderr) or ""):gsub("%s+$", "")
    vim.notify(out ~= "" and out or "No session running",
      res.code == 0 and vim.log.levels.INFO or vim.log.levels.WARN)
    session_checked_at = 0
    stop_timers()
  end)
end, { desc = "End the current writing session and log it" })

vim.api.nvim_create_user_command("WriteFastReport", function()
  run({ "report" }, function(res)
    local out = (res.stdout or ""):gsub("%s+$", "")
    vim.notify(out ~= "" and out or "No sessions recorded yet.", vim.log.levels.INFO)
  end)
end, { desc = "Show recent writing sessions and average WPM" })
