-- oops.lua — "something just went wrong": a 90-second rolling record of what
-- Matt was doing (keystrokes, app switches, clicks), dumped to an incident
-- directory on demand and handed to Claude, which logs the problem in the
-- vault's system problem log and tries to fix it.
--
-- Added 2026-09-12. Requested as: "press a keyboard shortcut when something did
-- not happen … goes back in time and looks at all the keyboard presses that
-- happened in the last 10 to 30 seconds … spins it off to Claude … saves this as
-- a problem stored in the persistent problem log … immediately tries to solve
-- that problem." This is the recorder + trigger half; the Claude half is the
-- nix-managed `oops` script (modules/home/darwin/oops.nix), reached through the
-- ~/.local/bin/oops symlink home-manager maintains.
--
-- Entry points (all end in M.trigger):
--   * ⌥` (hs.hotkey, bound below; was AeroSpace alt-backtick -> open -g, see there)
--   * Raycast "Oops" command  -> `open -g "hammerspoon://oops?text=…&prompt=0"`
--   * shell                   -> `hs -c 'oops.trigger("note")'`
--
-- Privacy: the buffer lives only in memory and is written to disk only when
-- Matt triggers it. While macOS secure-input is on (password fields, sudo
-- prompts) keys are counted but never recorded. Plain typing is coalesced into
-- one "typed: …" line per burst so the log reads like a story, not a keylog.
local M = {}

local BUFFER_SECONDS = 90
local STATE_ROOT = os.getenv("HOME") .. "/.local/state/oops"
local OOPS_BIN = os.getenv("HOME") .. "/.local/bin/oops"
-- A second ⌥` this soon after one that was SENT WITH A BLANK note is the same
-- complaint, not a new one: Matt bailed out of the box and pressed again to
-- type it. See M.trigger (2026-09-19 18:13).
local SUPERSEDE_SECONDS = 180

local buf = {} -- { t = epoch seconds, line = string }
local function shellQuote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
local hiddenKeys = 0 -- keys swallowed while secure input was on

-- ── app / window context (cached; AX title lookups are not free) ────────────
local ctx = { app = "?", title = "", at = 0, ws = "?" }

local function refreshContext(force)
  local now = hs.timer.secondsSinceEpoch()
  if not force and now - ctx.at < 1.0 then return end
  local app = hs.application.frontmostApplication()
  ctx.app = app and app:name() or "?"
  local win = hs.window.focusedWindow()
  local ok, title = pcall(function() return win and win:title() or "" end)
  ctx.title = ok and (title or "") or ""
  ctx.at = now
end

local function where()
  local w = "ws " .. ctx.ws .. " · " .. ctx.app
  if ctx.title ~= "" then w = w .. " — " .. ctx.title end
  return w
end

-- ── buffer ──────────────────────────────────────────────────────────────────
local function trim(now)
  local cutoff = now - BUFFER_SECONDS
  local first = 1
  while buf[first] and buf[first].t < cutoff do first = first + 1 end
  if first > 1 then
    local kept = {}
    for i = first, #buf do kept[#kept + 1] = buf[i] end
    buf = kept
  end
end

local function push(line, now)
  now = now or hs.timer.secondsSinceEpoch()
  -- the app watcher fires twice per activation; keep one line
  local last = buf[#buf]
  if last and last.line == line and now - last.t < 1.0 then return end
  buf[#buf + 1] = { t = now, line = line }
  if #buf % 200 == 0 then trim(now) end
end

-- ── key formatting ──────────────────────────────────────────────────────────
local MOD_ORDER = { { "fn", "fn" }, { "ctrl", "⌃" }, { "alt", "⌥" }, { "shift", "⇧" }, { "cmd", "⌘" } }
local NAMED = {
  ["return"] = "↩", ["delete"] = "⌫", ["forwarddelete"] = "⌦", ["escape"] = "⎋",
  ["tab"] = "⇥", ["space"] = "␣", ["up"] = "↑", ["down"] = "↓", ["left"] = "←", ["right"] = "→",
}

local function modString(f)
  local s = ""
  for _, m in ipairs(MOD_ORDER) do if f[m[1]] then s = s .. m[2] end end
  return s
end

-- ── trail (G1): what the recorder sees, kept 30 days, WITHOUT typed text ─────
-- 2026-10-07. Spec D3 (capture/spec-lifelog-bugs-checkoffs-sync-2026-10-06.md)
-- said yes to keeping this trail; Matt, 2026-10-07: "do you log my mouse
-- movements, my clicks, my keyboard presses? That seems like that would be
-- useful". lifelog's src_trail reads it and app-watch (scripts/app-watch) uses
-- it to spot rage clicks, retries and lost work. One JSON row per event in
-- ~/.local/state/oops/trail/YYYY-MM-DD.jsonl:
--   focus   an app switch (app, window title, workspace)
--   click   button, n (2 = double-click), x/y relative to its screen plus the
--           screen's index (main first, like screencapture -D) and size, so a
--           click can be marked on a Dayflow frame; travel = pointer path in
--           points since the last click; gap_ms = time since the last click
--   keys    shortcuts and named keys (⌘R, ↩, ⎋, ⇥, arrows), repeats folded (↓ ×7)
--   typing  a burst's size (ms long): n characters, del ⌫/⌦, syn synthetic keys
--           (pasted or dictated). NEVER the characters
--   scroll  a burst: n events, flips = direction changes (hunting)
--   drag    a left-button drag (select, move a window/file): from x/y to
--           x2/y2 on the start screen, dist in points, ms held
--   activity  one row per minute with any HUMAN input (2026-10-19, Oops
--           20261019-144653: "efficient and gets a high amount of detail"):
--           secs = seconds of the minute with input, keys, clicks, drags,
--           scrolls, move = pointer travel in points, so reading and pointing
--           without a click or key show up too. ts = the minute's start;
--           app/title/ws = where the last input went
-- Secure input (password fields, sudo) records nothing, not even a count.
local TRAIL_DIR = STATE_ROOT .. "/trail"
local TRAIL_KEEP_DAYS = 30
local EV, PROP = hs.eventtap.event.types, hs.eventtap.event.properties
local trailBuf = {}             -- { {day=, line=}, ... }, flushed every 5 s
local typing, scrolling, lastKey = nil, nil, nil
local travel, lastPos, lastClickAt = 0, nil, 0
local downAt, act = nil, nil    -- the left button's press (for drags); this minute's activity
os.execute("mkdir -p " .. shellQuote(TRAIL_DIR))

local function ms(x) return math.floor(x * 1000 + 0.5) end
local function plural(n, w) return n .. " " .. w .. (n == 1 and "" or "s") end

local function isoAt(t)
  local s = math.floor(t)
  local z = os.date("%z", s) -- -0700
  return os.date("%Y-%m-%dT%H:%M:%S", s) .. string.format(".%03d", math.floor((t - s) * 1000)) .. z:sub(1, 3) .. ":" .. z:sub(4, 5)
end

local function here() return { app = ctx.app, title = ctx.title, ws = ctx.ws } end
local function label(at) return at.app .. (at.title ~= "" and (" — " .. at.title) or "") end

local function emit(t, kind, at, fields, text)
  local row = { ts = isoAt(t), kind = kind, app = at.app, title = at.title, ws = at.ws, text = text }
  for k, v in pairs(fields or {}) do row[k] = v end
  local ok, line = pcall(hs.json.encode, row)
  if ok and line then trailBuf[#trailBuf + 1] = { day = os.date("%Y-%m-%d", math.floor(t)), line = line } end
end

local function closeTyping()
  if not typing then return end
  local b = typing
  typing = nil
  local parts = {}
  if b.n > 0 then parts[#parts + 1] = plural(b.n, "char") end
  if b.del > 0 then parts[#parts + 1] = b.del .. " ⌫" end
  if b.syn > 0 then parts[#parts + 1] = b.syn .. " pasted/dictated keys" end
  if #parts == 0 then return end
  emit(b.t, "typing", b.at, { n = b.n, del = b.del, syn = b.syn, ms = ms(b.last - b.t) },
    "typed " .. table.concat(parts, ", ") .. " in " .. label(b.at))
end

local function flushKey()
  if not lastKey then return end
  local k = lastKey
  lastKey = nil
  emit(k.t, "keys", k.at, { key = k.combo, count = k.count, syn = k.syn or nil },
    k.combo .. (k.count > 1 and (" ×" .. k.count) or "") .. " in " .. label(k.at))
end

local function closeScroll()
  if not scrolling then return end
  local s = scrolling
  scrolling = nil
  emit(s.t, "scroll", s.at, { n = s.n, flips = s.flips, ms = ms(s.last - s.t) },
    "scrolled" .. (s.flips >= 2 and (" back and forth (" .. s.flips .. " flips)") or "") .. " in " .. label(s.at))
end

local function closeActivity()
  if not act then return end
  local a = act
  act = nil
  local at = { app = a.app, title = a.title, ws = a.ws }
  local parts = { a.secs .. " s" }
  if a.keys > 0 then parts[#parts + 1] = plural(a.keys, "key") end
  if a.clicks > 0 then parts[#parts + 1] = plural(a.clicks, "click") end
  if a.drags > 0 then parts[#parts + 1] = plural(a.drags, "drag") end
  if a.scrolls > 0 then parts[#parts + 1] = plural(a.scrolls, "scroll event") end
  if a.move >= 1 then parts[#parts + 1] = "mouse " .. math.floor(a.move) .. " pt" end
  emit(a.min * 60, "activity", at, {
    secs = a.secs, keys = a.keys, clicks = a.clicks, drags = a.drags, scrolls = a.scrolls, move = math.floor(a.move),
  }, "input " .. table.concat(parts, ", ") .. " in " .. label(at))
end

-- count one human input event into this minute's activity row (amount: points moved)
local function actTouch(now, field, amount)
  local m = math.floor(now / 60)
  if act and act.min ~= m then closeActivity() end
  if not act then act = { min = m, secs = 0, lastSec = -1, keys = 0, clicks = 0, drags = 0, scrolls = 0, move = 0 } end
  local s = math.floor(now)
  if s ~= act.lastSec then act.secs, act.lastSec = act.secs + 1, s end
  if field then act[field] = act[field] + (amount or 1) end
  act.app, act.title, act.ws = ctx.app, ctx.title, ctx.ws
end

local function trailChar(now, syn, isDel)
  if not (typing and now - typing.last < 2.0 and typing.at.app == ctx.app and typing.at.title == ctx.title) then
    closeTyping()
    flushKey()
    typing = { t = now, last = now, at = here(), n = 0, del = 0, syn = 0 }
  end
  if isDel then typing.del = typing.del + 1 elseif syn then typing.syn = typing.syn + 1 else typing.n = typing.n + 1 end
  typing.last = now
end

local function trailKey(now, combo, syn)
  closeTyping()
  if lastKey and lastKey.combo == combo and now - lastKey.last < 1.5 and lastKey.at.app == ctx.app then
    lastKey.count, lastKey.last = lastKey.count + 1, now
    return
  end
  flushKey()
  lastKey = { t = now, last = now, combo = combo, count = 1, at = here(), syn = syn }
end

local screens, screensAt = nil, 0
local function screenAt(p)
  local now = hs.timer.secondsSinceEpoch()
  if not screens or now - screensAt > 10 then screens, screensAt = hs.screen.allScreens(), now end
  for i, sc in ipairs(screens) do
    local f = sc:fullFrame()
    if p.x >= f.x and p.x < f.x + f.w and p.y >= f.y and p.y < f.y + f.h then return i, f end
  end
end

local function trailClick(now, e, which, btn)
  closeTyping()
  flushKey()
  closeScroll()
  local p = e:location()
  local i, f = screenAt(p)
  local n = e:getProperty(PROP.mouseEventClickState) or 1
  local syn = e:getProperty(PROP.eventSourceUnixProcessID) ~= 0
  local at = here()
  emit(now, "click", at, {
    btn = btn, n = n, scr = i,
    x = math.floor(p.x - (f and f.x or 0)), y = math.floor(p.y - (f and f.y or 0)),
    sw = f and math.floor(f.w) or nil, sh = f and math.floor(f.h) or nil,
    travel = math.floor(travel), gap_ms = lastClickAt > 0 and ms(now - lastClickAt) or nil, syn = syn or nil,
  }, (n == 2 and "double-" or n >= 3 and "triple-" or "") .. which .. " in " .. label(at))
  travel, lastClickAt = 0, now
end

-- left button up: a drag when it moved 8+ pt since the press (the click row came first)
local function trailDrag(now, e, human)
  local d = downAt
  downAt = nil
  if not d then return end
  local p = e:location()
  local dist = math.sqrt((p.x - d.p.x) ^ 2 + (p.y - d.p.y) ^ 2)
  if dist < 8 then return end
  local i, f = screenAt(d.p)
  local ox, oy = f and f.x or 0, f and f.y or 0
  local at = here()
  emit(d.t, "drag", at, {
    x = math.floor(d.p.x - ox), y = math.floor(d.p.y - oy), x2 = math.floor(p.x - ox), y2 = math.floor(p.y - oy),
    scr = i, dist = math.floor(dist), ms = ms(now - d.t), syn = (not human) or nil,
  }, "dragged " .. math.floor(dist) .. " pt in " .. label(at))
  if human then actTouch(now, "drags") end
end

-- everything humanTap receives: pointer travel, drags, scroll bursts, and the
-- per-minute activity counts (human input only)
local function trailPointer(e, human)
  local ty = e:getType()
  local now = hs.timer.secondsSinceEpoch()
  if ty == EV.mouseMoved or ty == EV.leftMouseDragged or ty == EV.rightMouseDragged then
    local p = e:location()
    if lastPos then
      local d = math.abs(p.x - lastPos.x) + math.abs(p.y - lastPos.y)
      travel = travel + d
      if human then actTouch(now, "move", d) end
    end
    lastPos = p
  elseif ty == EV.keyDown then
    if human and not hs.eventtap.isSecureInputEnabled() then actTouch(now, "keys") end
  elseif ty == EV.leftMouseDown or ty == EV.rightMouseDown or ty == EV.otherMouseDown then
    if ty == EV.leftMouseDown then downAt = { t = now, p = e:location() } end
    if human then actTouch(now, "clicks") end
  elseif ty == EV.leftMouseUp then
    trailDrag(now, e, human)
  elseif ty == EV.scrollWheel then
    if human then actTouch(now, "scrolls") end
    local dy = e:getProperty(PROP.scrollWheelEventDeltaAxis1) or 0
    if not (scrolling and now - scrolling.last < 1.5 and scrolling.at.app == ctx.app) then
      closeScroll()
      refreshContext(false)
      scrolling = { t = now, last = now, at = here(), n = 0, flips = 0, dir = 0 }
    end
    if dy ~= 0 then
      if scrolling.dir ~= 0 and (dy > 0) ~= (scrolling.dir > 0) then scrolling.flips = scrolling.flips + 1 end
      scrolling.dir = dy
    end
    scrolling.n, scrolling.last = scrolling.n + 1, now
  end
end

local function flushTrail()
  local now = hs.timer.secondsSinceEpoch()
  if act and math.floor(now / 60) ~= act.min then closeActivity() end
  if typing and now - typing.last >= 2.0 then closeTyping() end
  if lastKey and now - lastKey.last >= 1.5 then flushKey() end
  if scrolling and now - scrolling.last >= 1.5 then closeScroll() end
  if #trailBuf == 0 then return end
  local byDay = {}
  for _, r in ipairs(trailBuf) do
    byDay[r.day] = byDay[r.day] or {}
    table.insert(byDay[r.day], r.line)
  end
  trailBuf = {}
  for day, lines in pairs(byDay) do
    local fh = io.open(TRAIL_DIR .. "/" .. day .. ".jsonl", "a")
    if fh then fh:write(table.concat(lines, "\n") .. "\n"); fh:close() end
  end
end

local function pruneTrail()
  local cutoff = os.date("%Y-%m-%d", os.time() - TRAIL_KEEP_DAYS * 86400)
  for f in hs.fs.dir(TRAIL_DIR) do
    local day = f:match("^(%d%d%d%d%-%d%d%-%d%d)%.jsonl$")
    if day and day < cutoff then os.remove(TRAIL_DIR .. "/" .. f) end
  end
end

M.trailTimer = hs.timer.doEvery(5, function()
  local ok, err = pcall(flushTrail)
  if not ok then print("oops.lua trail flush error: " .. tostring(err)) end
end)
pcall(pruneTrail)
M.trailPruneTimer = hs.timer.doEvery(6 * 3600, function() pcall(pruneTrail) end)
function M.trailFlush() flushTrail(); closeTyping(); flushKey(); closeScroll(); closeActivity(); flushTrail() end

local lastTyped = nil -- index into buf of the current "typed:" burst
local lastTypedAt = 0
local lastTypedWhere = ""

local function recordKey(e)
  local now = hs.timer.secondsSinceEpoch()
  if hs.eventtap.isSecureInputEnabled() then
    hiddenKeys = hiddenKeys + 1
    return
  end
  refreshContext(false)
  local f = e:getFlags()
  local code = e:getKeyCode()
  local name = hs.keycodes.map[code] or ("key" .. code)
  local chars = e:getCharacters(true) or ""
  local plain = not (f.cmd or f.ctrl or f.alt or f.fn)
  local printable = #chars == 1 and chars:byte() >= 32 and chars:byte() < 127

  -- trail: characters and deletes are only counted; ⌥+letter (Polish ą, ę, ś…)
  -- is typing too, not a shortcut
  local syn = e:getProperty(PROP.eventSourceUnixProcessID) ~= 0
  local altLetter = f.alt and not (f.cmd or f.ctrl or f.fn) and #name == 1
  if (plain and printable) or altLetter then
    trailChar(now, syn, false)
  elseif plain and (name == "delete" or name == "forwarddelete") then
    trailChar(now, syn, true)
  else
    trailKey(now, modString(f) .. (NAMED[name] or (code == 179 and "globe") or name), syn)
  end

  if plain and printable then
    -- coalesce a typing burst (same window, <2 s gap) into one line
    local here = where()
    if lastTyped and buf[lastTyped] and now - lastTypedAt < 2.0 and lastTypedWhere == here then
      buf[lastTyped].line = buf[lastTyped].line .. chars
    else
      push(string.format("[%s]  typed: %s", here, chars), now)
      lastTyped = #buf
      lastTypedWhere = here
    end
    lastTypedAt = now
    return
  end

  lastTyped = nil
  local key = NAMED[name] or name
  if plain and name == "space" then key = "␣" end
  push(string.format("[%s]  %s%s", where(), modString(f), key), now)
end

-- ── taps & watchers ─────────────────────────────────────────────────────────
M.keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local ok, err = pcall(recordKey, e)
  if not ok then print("oops.lua recordKey error: " .. tostring(err)) end
  return false
end)

M.clickTap = hs.eventtap.new({
  hs.eventtap.event.types.leftMouseDown,
  hs.eventtap.event.types.rightMouseDown,
  hs.eventtap.event.types.otherMouseDown,
}, function(e)
  local ok, err = pcall(function()
    refreshContext(true)
    local p = e:location()
    local which, btn = "click", "left"
    if e:getType() == EV.rightMouseDown then
      which, btn = "right-click", "right"
    elseif e:getType() == EV.otherMouseDown then -- 2 = middle, 3/4 = a mouse's back/forward side buttons
      local n = e:getProperty(PROP.mouseEventButtonNumber) or 2
      btn = n == 2 and "middle" or ("button" .. (n + 1))
      which = btn .. "-click"
    end
    lastTyped = nil
    push(string.format("[%s]  %s @ %.0f,%.0f", where(), which, p.x, p.y))
    trailClick(hs.timer.secondsSinceEpoch(), e, which, btn)
  end)
  if not ok then print("oops.lua click error: " .. tostring(err)) end
  return false
end)

M.appWatcher = hs.application.watcher.new(function(name, event)
  if event ~= hs.application.watcher.activated then return end
  hs.timer.doAfter(0.15, function()
    refreshContext(true)
    lastTyped = nil
    push(string.format("→ focus: %s", where()))
    local ok, err = pcall(function()
      closeTyping()
      flushKey()
      closeScroll()
      emit(hs.timer.secondsSinceEpoch(), "focus", here(), nil, "→ " .. label(here()))
    end)
    if not ok then print("oops.lua trail focus error: " .. tostring(err)) end
  end)
end)

-- Last time a HUMAN touched the keyboard/mouse, for ~/.claude/hooks/gui-input-guard.sh,
-- which refuses Claude GUI automation while Matt is active (Oops 20260913-154703:
-- a session's Raycast keyStrokes probes ate his typing). macOS's HIDIdleTime can't
-- serve: posted events reset it too. Events synthesized by a process carry that
-- process's pid; real hardware (incl. Karabiner's virtual HID keyboard) carries 0.
local HUMAN_FILE = STATE_ROOT .. "/last-human-input"
local humanWrittenAt = 0
M.humanTap = hs.eventtap.new({
  hs.eventtap.event.types.keyDown, hs.eventtap.event.types.leftMouseDown,
  hs.eventtap.event.types.rightMouseDown, hs.eventtap.event.types.otherMouseDown,
  hs.eventtap.event.types.mouseMoved, hs.eventtap.event.types.leftMouseDragged,
  hs.eventtap.event.types.rightMouseDragged, hs.eventtap.event.types.leftMouseUp,
  hs.eventtap.event.types.scrollWheel,
}, function(e)
  local human = e:getProperty(hs.eventtap.event.properties.eventSourceUnixProcessID) == 0
  local okT, errT = pcall(trailPointer, e, human)
  if not okT then print("oops.lua trail pointer error: " .. tostring(errT)) end
  local now = hs.timer.secondsSinceEpoch()
  if now - humanWrittenAt < 2 then return false end
  if not human then return false end
  humanWrittenAt = now
  local fh = io.open(HUMAN_FILE, "w")
  if fh then fh:write(string.format("%d\n", math.floor(now))); fh:close() end
  return false
end)

M.keyTap:start()
M.clickTap:start()
M.humanTap:start()
M.appWatcher:start()

-- ── the hotkey ──────────────────────────────────────────────────────────────
-- ⌥` is bound HERE, not in AeroSpace. It used to be AeroSpace `alt-backtick =
-- exec-and-forget /usr/bin/open -g hammerspoon://oops`, and in 2 of the first 3
-- hotkey-triggered incidents (2026-09-12 21:04, 2026-09-13 12:21) the first
-- press never arrived: the key tap logged ⌥`, the ring timer proves Hammerspoon
-- was idle, and no trigger ran — the press was lost between AeroSpace, `open`
-- and LaunchServices, and Matt pressed again 10–15 s later. A Carbon hotkey in
-- the process that owns the recorder has no hop to lose. Keycode 50 = the grave
-- key, whatever the layout (Matt types on the Polish layout).
-- The hammerspoon://oops URL stays for Raycast ("Oops" with a note) and shell.
M.hotkey = hs.hotkey.bind({ "alt" }, 50, function() M.trigger(nil, {}) end)

-- ── screenshots ─────────────────────────────────────────────────────────────
-- 2026-10-05 (Oops 20261005-164023): "refactor the oops claude service so it
-- instead uses dayflow's screenshots? that way we dont have 2 services taking
-- screenshots consistently". Oops no longer runs a capture loop of its own: the
-- 2 frames/s ring (oops_ring.zsh, `screencapture` into a RAM disk, 2026-09-13)
-- is retired to backup-20261005-dayflow-frames/, and at the trigger
-- oops_dayflow.py copies Dayflow's frames for the last 90 s (one per 5-10 s, of
-- the active display) into screens/. The only frame Oops still takes is the
-- one AT the trigger, of the display with the focused window, by
-- /usr/sbin/screencapture in an hs.task (it inherits Hammerspoon's Screen
-- Recording grant, 2026-09-12). Not hs.screen:snapshot(): with ScreenCaptureKit
-- degraded on 2026-10-05 one snapshot held Hammerspoon's main thread (the key
-- tap, every hotkey) for 5-18 s and still returned nothing.
-- screencapture -D numbers displays like hs.screen.allScreens(): main first.
local function focusedDisplay()
  local win = hs.window.focusedWindow()
  local scr = win and win:screen()
  for i, sc in ipairs(scr and hs.screen.allScreens() or {}) do
    if sc:id() == scr:id() then return i end
  end
  return 1
end

-- A timeline of where() (one entry per change) so each Dayflow frame gets its
-- workspace/app/window in INDEX.txt; oops_dayflow.py gets it as a file.
local DAYFLOW_SCRIPT = os.getenv("HOME") .. "/.hammerspoon/oops_dayflow.py"
local PYTHON = "/etc/profiles/per-user/matth/bin/python3"
local whereLog = {} -- { {t=, w=}, ... } oldest first, one entry per change

M.whereTimer = hs.timer.doEvery(1, function()
  local ok, err = pcall(function()
    local now = hs.timer.secondsSinceEpoch()
    local w = where()
    if not whereLog[#whereLog] or whereLog[#whereLog].w ~= w then whereLog[#whereLog + 1] = { t = now, w = w } end
    while #whereLog > 1 and whereLog[2].t < now - BUFFER_SECONDS - 5 do table.remove(whereLog, 1) end
  end)
  if not ok then print("oops.lua where timer error: " .. tostring(err)) end
end)

-- ── trigger ─────────────────────────────────────────────────────────────────
local function writeFile(path, text)
  local fh = assert(io.open(path, "w"))
  fh:write(text)
  fh:close()
end

-- The rest of the trigger, once the note is known.
local function finish(dir, note, opts)
  writeFile(dir .. "/note.txt", note .. "\n")

  -- front.txt: everything about the input state at the trigger that has bitten
  -- Matt before — stuck modifiers (Wispr/kanata), secure input holding the
  -- keyboard, the wrong input source (US vs Polish), a screen full of dialogs.
  local mods = {}
  for k, v in pairs(hs.eventtap.checkKeyboardModifiers() or {}) do if v then mods[#mods + 1] = k end end
  local pos = hs.mouse.absolutePosition()
  local fw = hs.window.focusedWindow()
  local fr = fw and fw:frame()
  local ax = hs.accessibilityState()
  local rec = hs.screenRecordingState and hs.screenRecordingState(false)
  local layout = hs.keycodes.currentLayout and hs.keycodes.currentLayout() or "?"
  local secure = hs.eventtap.isSecureInputEnabled()
  local hsver = hs.processInfo.version
  local lines2 = {
    "when: " .. os.date("%Y-%m-%d %H:%M:%S"),
    "workspace: " .. tostring(ctx.ws),
    "app: " .. tostring(ctx.app),
    "window: " .. tostring(ctx.title),
    "window frame: " .. (fr and string.format("%.0fx%.0f @ %.0f,%.0f", fr.w, fr.h, fr.x, fr.y) or "none"),
    "mouse: " .. string.format("%.0f,%.0f", pos.x, pos.y),
    "modifiers held at trigger: " .. (#mods > 0 and table.concat(mods, "+") or "none"),
    "keyboard layout: " .. tostring(layout),
    "secure input on: " .. tostring(secure) .. (secure and "  <- a process holds the keyboard; see context.md 'secure input owner'" or ""),
    "hammerspoon " .. hsver .. ": accessibility=" .. tostring(ax) .. " screen-recording=" .. tostring(rec),
    "idle seconds before trigger: " .. tostring(math.floor(hs.host.idleTime())),
  }
  writeFile(dir .. "/front.txt", table.concat(lines2, "\n") .. "\n")

  -- the Hammerspoon console: errors from hotkeys/taps/spoons live only here
  local ok, con = pcall(function() return hs.console.getConsole(false) end)
  if ok and type(con) == "string" then
    local tailLines, n = {}, 0
    for line in con:gmatch("[^\n]+") do tailLines[#tailLines + 1] = line end
    local start = math.max(1, #tailLines - 150)
    local out = {}
    for i = start, #tailLines do out[#out + 1] = tailLines[i] end
    writeFile(dir .. "/hammerspoon-console.txt", "# last " .. #out .. " Hammerspoon console lines\n" .. table.concat(out, "\n") .. "\n")
  end

  if opts.dry then
    hs.alert.show("Oops (dry run) → " .. dir, 1.5)
    return dir
  end

  M._last = { dir = dir, note = note, t = hs.timer.secondsSinceEpoch() }
  hs.task.new(OOPS_BIN, function(code, _, err)
    if code ~= 0 then
      hs.alert.show("oops launcher failed (" .. tostring(code) .. ")", 2)
      print("oops launcher stderr: " .. tostring(err))
    end
  end, { dir }):start()
  -- no success pop-up: Matt does not want a message that Oops ran (2026-09-13)
  return dir
end

-- Ask for the note in a separate osascript process. hs.dialog.textPrompt is a
-- BLOCKING call: while it was up, every other Hammerspoon hotkey and event tap
-- (brightness, Cmd+Delete, this recorder) stalled — found 2026-09-12 on the
-- first test. osascript's dialog runs outside Hammerspoon, so nothing blocks.
local function askNote(dir, opts)
  local script = [[
    set r to display dialog "Blank = let Claude infer it from the last 90 s of keys. A change request works too." ¬
      default answer "" with title "Oops — what went wrong?" ¬
      buttons {"Cancel", "Send to Claude"} default button "Send to Claude" with icon caution
    return text returned of r
  ]]
  M._promptDir = dir
  M._promptTask = hs.task.new("/usr/bin/osascript", function(code, out, _)
    M._promptTask = nil
    M._promptDir = nil
    if code ~= 0 then -- Cancel / Escape / killed
      -- Never delete the dir of a session that is already running on it.
      if not opts.supersede then os.execute("rm -rf " .. shellQuote(dir)) end
      return
    end
    local text = (out or ""):gsub("%s+$", "")
    if opts.supersede then
      -- No second recording, no second session: hand the note to the one that
      -- is already working this incident. Blank again = nothing to add.
      if text ~= "" then
        writeFile(dir .. "/note.txt", text .. "\n")
        M._last.note = text
        hs.task.new(OOPS_BIN, function(c, _, e)
          if c ~= 0 then print("oops --note failed (" .. tostring(c) .. "): " .. tostring(e)) end
        end, { "--note", dir, text }):start()
        hs.alert.show("→ Oops " .. (dir:match("[^/]+$") or ""), 1.5)
      end
      return
    end
    finish(dir, text, opts)
  end, { "-e", script }):start()
end

-- note: string or nil. opts.prompt (default true): ask for a note in a dialog
-- when none was given. opts.dry: gather the incident but do not launch Claude.
function M.trigger(note, opts)
  opts = opts or {}
  if note == nil and opts.prompt ~= false and M._promptTask then
    -- The note dialog is already up (Matt pressed again, or pressed before it
    -- had focus): bring it forward. Do NOT start over — that threw away the
    -- first, more relevant, 90 s window and the dir (2026-09-13).
    local osa = hs.application.get("osascript")
    if osa then osa:activate(true) end
    return M._promptDir
  end
  -- Pressed again right after sending a BLANK note (⌥`, ↩ on an empty box, then
  -- ⌥` again to actually type it). That is one complaint, and a second
  -- recording costs a second Opus session and a second problem-log entry
  -- (2026-09-19 18:13:49 / 18:14:21, 32 s apart, both on "better display").
  -- Keep the FIRST recording — its 90 s is the window closest to the failure,
  -- the second is half Matt fighting the Oops box — and ask for the note again
  -- against that dir; askNote's supersede branch delivers it to the live tab.
  if note == nil and opts.prompt ~= false and M._last and M._last.note == ""
      and hs.timer.secondsSinceEpoch() - M._last.t <= SUPERSEDE_SECONDS then
    askNote(M._last.dir, { supersede = true })
    return M._last.dir
  end
  local now = hs.timer.secondsSinceEpoch()
  trim(now)
  refreshContext(true)

  local ts = os.date("%Y%m%d-%H%M%S")
  local dir = STATE_ROOT .. "/" .. ts
  os.execute("mkdir -p " .. shellQuote(dir))

  -- keys.log: relative seconds before the trigger, oldest first
  local lines = { "# last " .. BUFFER_SECONDS .. " s before the Oops trigger (" .. os.date("%Y-%m-%d %H:%M:%S") .. "); T-0 is the trigger" }
  if hiddenKeys > 0 then
    lines[#lines + 1] = string.format("# %d keystroke(s) hidden (secure input was on)", hiddenKeys)
  end
  for _, e in ipairs(buf) do
    lines[#lines + 1] = string.format("T-%05.1fs  %s", now - e.t, e.line)
  end
  writeFile(dir .. "/keys.log", table.concat(lines, "\n") .. "\n")
  hiddenKeys = 0

  -- screenshots: the screen right now, then Dayflow's frames for the window,
  -- both in the background while the note box is up. oops_dayflow.py starts
  -- when the capture is done, folds its INDEX.tail in and writes INDEX.txt last.
  os.execute("mkdir -p " .. shellQuote(dir .. "/screens"))
  local wl = {}
  for _, e in ipairs(whereLog) do wl[#wl + 1] = string.format("%.3f\t%s", e.t, e.w) end
  writeFile(dir .. "/screens/.where", table.concat(wl, "\n") .. "\n")
  local here = where()
  local function pullDayflow()
    M.dayflowTask = hs.task.new(PYTHON, function(code, _, err)
      if code ~= 0 then print("oops_dayflow.py exited " .. tostring(code) .. ": " .. tostring(err)) end
    end, { "-I", DAYFLOW_SCRIPT, dir .. "/screens", string.format("%.3f", now), tostring(BUFFER_SECONDS), dir .. "/screens/.where" })
    M.dayflowTask:start()
  end
  local shot = hs.task.new("/usr/sbin/screencapture", function(code)
    if code == 0 then writeFile(dir .. "/screens/INDEX.tail", "T-000.0s.jpg  " .. here .. "  (at trigger)\n") end
    pullDayflow()
  end, { "-x", "-D", tostring(focusedDisplay()), "-t", "jpg", dir .. "/screens/T-000.0s.jpg" })
  M.shotTask = shot
  if shot:start() then
    -- a wedged capture must not hold up Dayflow's frames
    hs.timer.doAfter(10, function() if shot:isRunning() then shot:terminate() end end)
  else
    pullDayflow()
  end

  if note == nil and opts.prompt ~= false then
    M._promptDir = dir
    askNote(dir, opts)
    return dir
  end
  return finish(dir, note or "", opts)
end

function M.count() return #buf end
function M.ws() return ctx.ws end

-- Seed the workspace at load (and re-sync every 30 s in case an event was
-- missed): before the first switch after a reload every line said "ws ?".
local function syncWorkspace()
  hs.task.new("/opt/homebrew/bin/aerospace", function(code, out)
    if code == 0 and out and out ~= "" then ctx.ws = (out:gsub("%s+$", "")) end
  end, { "list-workspaces", "--focused" }):start()
end
syncWorkspace()
M.wsTimer = hs.timer.doEvery(30, syncWorkspace)

-- AeroSpace exec-on-workspace-change -> hammerspoon://oops-ws?prev=1&cur=2
hs.urlevent.bind("oops-ws", function(_, params)
  params = params or {}
  M.prevWs, M.wsChangedAt = params.prev, hs.timer.secondsSinceEpoch() -- read by bitwarden_follow.lua
  ctx.ws = params.cur or "?"
  ctx.at = 0 -- force a title refresh on the next key
  lastTyped = nil
  push(string.format("→ workspace %s → %s", params.prev or "?", ctx.ws))
end)

-- hammerspoon://oops?text=…&prompt=0&dry=1
hs.urlevent.bind("oops", function(_, params)
  params = params or {}
  local note = params.text
  local prompt = params.prompt ~= "0"
  if note ~= nil then prompt = false end
  M.trigger(note, { prompt = prompt, dry = params.dry == "1" })
end)

return M
