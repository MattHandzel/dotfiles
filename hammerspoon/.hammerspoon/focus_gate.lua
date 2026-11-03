-- focus_gate.lua — Focus Mode on the Mac: a distracting app takes 15 s to reach.
--
-- Added 2026-09-14 (Matt: "when these applications are in focus mode, it takes
-- me 15 seconds to get to them … they go to their own workspaces … even if I
-- click on those [in the top bar], it still takes [the delay]"). The macOS port
-- of the laptop's focus-mode-enforcer.sh (Hyprland event socket), which never
-- came across in the migration: only focus_app's keybind gate did, and the
-- nix `focus-app` hotkeys do not call it.
--
-- Pieces, all keyed on the /tmp/focus_mode flag (toggle-focus-mode):
--   * distracting list  focus-distracting-apps (from ~/notes/resources/
--                       focus-mode-apps.md), matched as case-insensitive
--                       substrings of the workspace name or any app on it.
--   * own workspaces    aerospace.nix routes Discord/Spotify/Beeper/Superhuman/
--                       WhatsApp (ws "wasistlos") to named
--                       workspaces; a distracting app activated somewhere else
--                       is moved to the workspace named after it.
--   * the bar           sketchybar plugins/aerospace.sh drops those pills.
--   * this gate         EVERY route onto a distracting workspace (alt-ctrl
--                       hotkey, bar click, alt-tab, Cmd-Tab, Dock, a link)
--                       arrives here via AeroSpace exec-on-workspace-change ->
--                       hammerspoon://focus-gate-ws. It bounces back to the
--                       last safe workspace and shows a 15 s countdown with
--                       Cancel (drawn here, below): wait it out -> you land
--                       there and that workspace stays unlocked while you
--                       are on it and for UNLOCK_GRACE after you first leave
--                       it (returning does not restart the grace);
--                       Cancel -> you stay put. Asking again
--                       yourself reopens the countdown at once; only an app
--                       raising itself stays silently bounced for 45 s.
--
-- Unlocks are stamped with the flag file's mtime, so turning focus mode off
-- and on again re-locks everything without any IPC from toggle-focus-mode.
-- Log: Hammerspoon console, lines prefixed "focus-gate:".

local M = {}

local AEROSPACE = "/opt/homebrew/bin/aerospace"
local FLAG = "/tmp/focus_mode"
local BIN = "/etc/profiles/per-user/" .. (os.getenv("USER") or "matth") .. "/bin/"
local DELAY = 15
local CANCEL_COOLDOWN = 45
-- An unlock lasts while you are on that workspace and for this long after you
-- first leave it (a quick hop back for a code is free; hopping back does not
-- restart the clock), then it locks again. It used
-- to last until focus mode was turned off, and the flag stayed on from 09-20
-- to 09-22, so one wait unlocked Superhuman/Beeper for two days (Oops
-- 20260922-102452).
local UNLOCK_GRACE = 120

local function log(fmt, ...) print("focus-gate: " .. string.format(fmt, ...)) end

-- ── distracting terms ────────────────────────────────────────────────────────
-- Loaded asynchronously, so a slow or hung script can never block Hammerspoon's
-- main thread; refreshed every 60 s so edits to the list take effect.
local terms = {}
local function loadTerms()
  hs.task.new(BIN .. "focus-distracting-apps", function(code, out)
    if code ~= 0 then return end
    local t = {}
    for term in (out or ""):gmatch("[^|%s]+") do t[#t + 1] = term:lower() end
    terms = t
  end):start()
end

local function isDistracting(s)
  s = (s or ""):lower()
  for _, term in ipairs(terms) do
    if s:find(term, 1, true) then return true end
  end
  return false
end

-- ── state ────────────────────────────────────────────────────────────────────
local function flagStamp() return hs.fs.attributes(FLAG, "modification") end

local unlocked = {} -- workspace -> { stamp = flag stamp, left = os.time() you left it, or nil }
local denied = {}   -- workspace -> { t = os.time() of the last Cancel, stamp }
local safe = nil    -- last workspace seen that is not gated
local pending = nil -- workspace whose countdown is open
local seq = 0       -- bumps on every workspace event

local function aero(args, cb)
  hs.task.new(AEROSPACE, cb or function() end, args):start()
end

-- Triage (scripts/message-triage) is the sanctioned way to message during focus,
-- so it is never gated. Until the darwin switch gives Triage.app its own workspace,
-- its Chrome window lives on 'beeper', and the gate held it back like raw Beeper:
-- on 2026-10-06 Matt hit the countdown five times in four minutes and turned Focus
-- Mode off to get in, which the triage server undid every 30 s. When the window that
-- ends up focused is Triage, let it through and put raw Beeper away. Adding
-- 'triage' to focus-mode-apps.md gates it again (SPEC.md decision 5).
local TRIAGE_SETTLE = 0.35 -- focus-app focuses the window just after summoning the workspace
-- Triage's Transcribe button (2026-10-06) opens one message in Beeper for about a
-- second, because Beeper only transcribes a voice note it draws, then switches back.
-- The triage server touches WAKE just before. That hop is Triage working, not Matt
-- reaching for Beeper, so it is not gated, and Beeper is not hidden mid-draw.
local WAKE, WAKE_SECS = "/tmp/triage_beeper_wake", 8
function M.triageWake(ws)
  if ws ~= "beeper" then return false end
  local m = hs.fs.attributes(WAKE, "modification")
  return m ~= nil and os.time() - m <= WAKE_SECS
end
local function isTriage(line)
  for _, term in ipairs(terms) do
    if term == "triage" then return false end
  end
  local app, title = (line or ""):match("^([^|]*)|([^\n]*)")
  return app == "Triage" or (app == "Google Chrome" and (title or ""):match("^Triage") ~= nil)
end

-- cb(true) when `ws` is distracting by name or by any app on it.
local function checkWorkspace(ws, cb)
  if isDistracting(ws) then return cb(true) end
  aero({ "list-windows", "--workspace", ws, "--format", "%{app-name}" }, function(code, out)
    if code ~= 0 then return cb(false) end
    for app in (out or ""):gmatch("[^\n]+") do
      if isDistracting(app) then return cb(true) end
    end
    cb(false)
  end)
end

-- ── the countdown ────────────────────────────────────────────────────────────
-- Drawn natively (hs.canvas + a 1 s timer), not by shelling out to
-- focus-delay-gate: that osascript dialog could not be replaced cleanly when a
-- second request arrived (killing its process tree hung Hammerspoon in testing,
-- 2026-09-14), and it showed no live countdown. Cancel = click the button.
-- NOT Escape: a global Escape hotkey swallowed vim's Esc in kitty while the
-- countdown sat on screen, cancelling a gate Matt was waiting out (Oops
-- 20260915-100614).
local gate = nil -- { ws, canvas, timer }

local MOCHA = {
  base = { hex = "#1e1e2e" }, text = { hex = "#cdd6f4" }, sub = { hex = "#a6adc8" },
  mauve = { hex = "#cba6f7" }, surface = { hex = "#45475a" }, peach = { hex = "#fab387" },
}

local function closeGate()
  if not gate then return end
  gate.timer:stop()
  gate.canvas:delete()
  gate, pending = nil, nil
end

local function finishGate(ok)
  if not gate then return end
  local ws = gate.ws
  closeGate()
  if ok then
    local stamp = flagStamp()
    if stamp then unlocked[ws] = { stamp = stamp } end
    log("unlocked '%s'", ws)
    aero({ "workspace", ws })
  else
    denied[ws] = { t = os.time(), stamp = flagStamp() }
    log("cancelled '%s' — staying focused", ws)
  end
end

local function runGate(ws)
  -- The newest request wins: a countdown for another workspace is dropped and
  -- the full delay starts over (tested 2026-09-14: without this, asking for
  -- Discord during Spotify's countdown landed you on Spotify).
  closeGate()
  pending = ws
  log("gating '%s' (%ds)", ws, DELAY)

  local scr = hs.screen.mainScreen():frame()
  local W, H = 440, 132
  local c = hs.canvas.new({ x = scr.x + (scr.w - W) / 2, y = scr.y + scr.h * 0.28, w = W, h = H })
  c:level(hs.canvas.windowLevels.modalPanel)
  c:behavior({ "canJoinAllSpaces", "stationary" })
  c:clickActivating(false)
  c:appendElements(
    { type = "rectangle", action = "strokeAndFill", fillColor = MOCHA.base, strokeColor = MOCHA.peach,
      strokeWidth = 2, roundedRectRadii = { xRadius = 12, yRadius = 12 } },
    { type = "text", text = "󱫠  Focus Mode", textColor = MOCHA.peach, textSize = 13,
      textFont = "JetBrainsMono Nerd Font", frame = { x = 20, y = 14, w = W - 40, h = 20 } },
    { id = "msg", type = "text", text = "", textColor = MOCHA.text, textSize = 17,
      textFont = "JetBrainsMono Nerd Font", frame = { x = 20, y = 40, w = W - 40, h = 26 } },
    { id = "bar", type = "rectangle", action = "fill", fillColor = MOCHA.mauve,
      roundedRectRadii = { xRadius = 2, yRadius = 2 }, frame = { x = 20, y = 74, w = 0, h = 4 } },
    { id = "cancel", type = "rectangle", action = "fill", fillColor = MOCHA.surface,
      roundedRectRadii = { xRadius = 6, yRadius = 6 }, frame = { x = W - 150, y = H - 44, w = 130, h = 30 },
      trackMouseUp = true },
    { type = "text", text = "Cancel", textColor = MOCHA.text, textSize = 13, textAlignment = "center",
      textFont = "JetBrainsMono Nerd Font", frame = { x = W - 150, y = H - 38, w = 130, h = 20 } },
    { type = "text", text = "stay focused", textColor = MOCHA.sub, textSize = 12,
      textFont = "JetBrainsMono Nerd Font", frame = { x = 20, y = H - 37, w = 200, h = 20 } }
  )
  c:mouseCallback(function(_, msg, id)
    -- Deferred: deleting a canvas from inside its own mouse callback crashes
    -- Hammerspoon outright (it did, 2026-09-14).
    if id == "cancel" and msg == "mouseUp" then
      hs.timer.doAfter(0, function() finishGate(false) end)
    end
  end)

  local left = DELAY
  local function draw()
    c["msg"].text = string.format("Opening %s in %ds…", ws, left)
    c["bar"].frame = { x = 20, y = 74, w = (W - 40) * (DELAY - left) / DELAY, h = 4 }
  end
  draw()
  c:show()

  gate = {
    ws = ws,
    canvas = c,
    timer = hs.timer.doEvery(1, function()
      left = left - 1
      -- Focus mode turned off mid-countdown: nothing left to gate, go there.
      if left <= 0 or not flagStamp() then return finishGate(true) end
      draw()
    end),
  }
end

-- `auto` = the switch came from an app raising itself (onActivated), not from
-- Matt. Only that path honours the Cancel cooldown. A switch Matt makes himself
-- always shows the countdown. A silent bounce looked like a broken hotkey: ⌃⌥M
-- pressed ~25 times with no timer (Oops 20260915-100614).
function M.onWorkspace(prev, cur, auto)
  seq = seq + 1
  local mySeq = seq
  if M.triageWake(cur) then
    log("Triage is transcribing a voice note in Beeper: not gated")
    return
  end
  -- Until the darwin switch gives Triage.app its own workspace, its Chrome window
  -- shares 'beeper' with raw Beeper, so ⌃⌥H showed Beeper beside it. Whenever
  -- Triage is what got focused there, put Beeper away, focus mode or not (2026-10-06).
  if cur == "beeper" then
    hs.timer.doAfter(TRIAGE_SETTLE, function()
      aero({ "list-windows", "--focused", "--format", "%{app-name}|%{window-title}" }, function(code, out)
        if code ~= 0 or not isTriage(out) then return end
        local b = hs.application.get("Beeper")
        if b and not b:isHidden() then b:hide() end
      end)
    end)
  end
  local stamp = flagStamp()
  if not stamp then
    unlocked, denied, safe = {}, {}, cur
    return
  end
  if not cur or cur == "" then return end
  local now = os.time()
  for ws, u in pairs(unlocked) do
    if u.stamp ~= stamp or (u.left and now - u.left >= UNLOCK_GRACE) then
      unlocked[ws] = nil
      log("re-locked '%s'", ws)
    end
  end
  -- The grace runs from the FIRST time you leave after the wait; coming back
  -- does not restart it. It used to (left = nil on return), so flipping
  -- notetaker <-> Beeper every minute kept one wait alive indefinitely (Oops
  -- 20260922-105209: unlocked 10:45:43, still free at 10:52).
  if prev and prev ~= cur and unlocked[prev] and not unlocked[prev].left then unlocked[prev].left = now end
  if unlocked[cur] then
    safe = cur
    return
  end
  checkWorkspace(cur, function(bad)
    if not bad then
      safe = cur
      return
    end
    -- A newer switch already took you somewhere else; that one gets checked.
    if mySeq ~= seq then return end
    hs.timer.doAfter(TRIAGE_SETTLE, function()
      aero({ "list-windows", "--focused", "--format", "%{app-name}|%{window-title}" }, function(code, out)
        if mySeq ~= seq then return end
        if code == 0 and isTriage(out) then
          log("letting Triage through on '%s'", cur)
          local b = hs.application.get("Beeper")
          if b and not b:isHidden() then b:hide() end
          return
        end
        local back = safe
        if not back or back == cur then back = (prev ~= cur and prev) or "1" end
        aero({ "workspace", back })
        if pending == cur then return end -- this countdown is already open
        local d = denied[cur]
        if auto and d and d.stamp == stamp and os.time() - d.t < CANCEL_COOLDOWN then return end
        runGate(cur)
      end)
    end)
  end)
end

-- A distracting app brought forward on a workspace that is not its own (Dock,
-- Cmd-Tab, a notification) never changes workspace, so nothing above fires.
-- Send its window home, to the workspace named after the app, then gate that.
local function onActivated(name)
  if not flagStamp() or not isDistracting(name) then return end
  if M.triageWake("beeper") and (name or ""):lower():find("beeper", 1, true) then return end
  hs.timer.doAfter(0.3, function()
    aero({ "list-windows", "--focused", "--format", "%{window-id}|%{app-name}|%{workspace}" }, function(code, out)
      if code ~= 0 then return end
      local id, app, ws = (out or ""):match("^(%d+)|([^|]*)|([^\n]*)")
      if not id or not isDistracting(app) or isDistracting(ws) then return end
      local home = app:lower():match("^(%S+)")
      log("'%s' surfaced on '%s' — moving it to '%s'", app, ws, home)
      aero({ "move-node-to-workspace", "--window-id", id, home }, function()
        M.onWorkspace(ws, home, true)
      end)
    end)
  end)
end

-- For debugging from a shell:  hs -c 'return focusGate.state()'
function M.state()
  local u, d = {}, {}
  for k in pairs(unlocked) do u[#u + 1] = k end
  for k in pairs(denied) do d[#d + 1] = k end
  return string.format("flag=%s gate=%s safe=%s unlocked=[%s] denied=[%s]",
    tostring(flagStamp() ~= nil), gate and gate.ws or "-", tostring(safe),
    table.concat(u, ","), table.concat(d, ","))
end

-- ── wiring ───────────────────────────────────────────────────────────────────
loadTerms()
M.termsTimer = hs.timer.doEvery(60, loadTerms)

aero({ "list-workspaces", "--focused" }, function(code, out)
  if code == 0 then safe = (out or ""):match("^%s*(.-)%s*$") end
end)

-- AeroSpace exec-on-workspace-change -> hammerspoon://focus-gate-ws?prev=1&cur=2
hs.urlevent.bind("focus-gate-ws", function(_, params)
  M.onWorkspace(params.prev, params.cur)
end)

M.appWatcher = hs.application.watcher.new(function(name, event)
  if event == hs.application.watcher.activated then onActivated(name) end
end)
M.appWatcher:start()

return M
