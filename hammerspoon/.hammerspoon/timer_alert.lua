-- leader-timer "done" alarm. Added 2026-09-22 (Oops 20260922-105249).
--
-- The Raycast "Timer (minutes)" countdown (leader-timer, a launchd job) used to
-- end with an osascript banner + `afplay Glass`. Both fired, but Matt noticed
-- neither: the banner is a 5 s "Script Editor" toast, and afplay goes to the
-- default output, which was the Jabra USB headset, muted. The job now calls
-- hammerspoon://leader-timer-done?title=…&body=…, and this module:
--   * shows a big alert on every screen that STAYS until Matt presses a key or
--     clicks (auto-closes after 15 min so a forgotten one can't linger forever);
--     2026-10-13 (Oops 20261013-162144): only a key or click after a PAUSE in
--     his input counts. With "any key 0.8 s after it shows", the next keystroke
--     of whatever he was typing closed it unseen: 98 of 144 alarms in
--     leader-timer.log were dismissed within 2 s (the 16:08:53 "pomo" one
--     mid-sentence in an Airbnb message), so to him the timer "stopped working".
--   * plays Glass on the default output AND the built-in speakers, briefly
--     unmuting a muted device and restoring its mute state afterwards.
--     2026-10-05 (Oops 20261005-164000): when the default output is something
--     Matt wears (USB/Bluetooth headset, earphones in the jack) the chime stays
--     in it and the speakers keep quiet ("the timer sound is played through my
--     speakers even if i have earphones or a headset").
--   * Resolve Cycle (kind=resolve, Raycast "Resolve Cycle"), 2026-10-30
--     (Oops 20261030-093441): Matt dismissed the normal alarm and kept working
--     without noticing ("when the timer goes off, I actually don't stop").
--     A purple full-screen overlay counts down GRACE s while input still
--     passes (finish the sentence), then turns opaque and swallows every key
--     and click for BREATH s, then only Return lets him back. Locking the
--     screen or AUTO_CLOSE releases it, so it can never trap the password.
-- Extensions required up front: lazy-loading hs.audiodevice from inside the
-- URL callback overflowed the stack on the first test (10:57:55).
require("hs.alert"); require("hs.audiodevice"); require("hs.sound"); require("hs.eventtap"); require("hs.caffeinate")
-- Assign, not just require: hs.canvas would otherwise still go through the
-- lazy loader, whose print() overflowed the stack in the URL callback.
-- (Resolve Cycle test 2026-10-30: hs.canvas, hs.audiodevice, hs.sound.)
for _, ext in ipairs({ "alert", "audiodevice", "sound", "eventtap", "caffeinate", "canvas", "screen" }) do
  hs[ext] = require("hs." .. ext)
end

local M = {}

local SOUND = "/System/Library/Sounds/Glass.aiff"
local LOG = os.getenv("HOME") .. "/.local/state/leader-timer.log"
local AUTO_CLOSE = 15 * 60
local PAUSE = 1.5 -- s without any key/click before one dismisses the alert

local shown, dismissTap, autoClose = {}, nil, nil
M.GRACE, M.BREATH = 10, 5 -- s; fields so a test can shorten them. BREATH 20 → 5 (Oops 20261102-151533)
local RETURN_KEYS = { [36] = true, [76] = true } -- return, keypad enter
local resolve = nil -- { canvases, tap, ticker, autoClose }

local function log(msg)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. msg .. "\n"); f:close() end
end

local function dismiss(why)
  if #shown > 0 then log("dismissed (" .. tostring(why or "api") .. ")") end
  for _, id in ipairs(shown) do hs.alert.closeSpecific(id, 0.3) end
  shown = {}
  if dismissTap then dismissTap:stop(); dismissTap = nil end
  if autoClose then autoClose:stop(); autoClose = nil end
end

-- Play on one device; unmute it for the length of the sound if it is muted.
local function ring(dev)
  if not dev then return "none" end
  local snd = hs.sound.getByFile(SOUND)
  if not snd then return dev:name() .. ": no sound file" end
  local wasMuted = dev:muted()
  if wasMuted then dev:setMuted(false) end
  snd:device(dev:uid())
  snd:play()
  if wasMuted then
    hs.timer.doAfter(math.max(snd:duration(), 1) + 0.5, function() dev:setMuted(true) end)
  end
  return string.format("%s (muted=%s vol=%.0f)", dev:name(), tostring(wasMuted), dev:outputVolume() or -1)
end

-- A headset or earphones: USB (the Jabra), Bluetooth (AirPods), or the
-- built-in jack ("External Headphones", or the Headphones data source).
local function worn(dev)
  local t = dev:transportType()
  if t == "USB" or t == "Bluetooth" or t == "Bluetooth LE" then return true end
  local src = dev:currentOutputDataSource()
  return (dev:name() .. " " .. (src and src:name() or "")):lower():find("headphone") ~= nil
end

local function builtinSpeakers()
  for _, d in ipairs(hs.audiodevice.allOutputDevices()) do
    if d:transportType() == "Built-in" and not worn(d) then return d end
  end
end

-- gate(now) is true for a key/click that comes PAUSE s or more after the
-- previous one (or after the alert showed, t0), plus the idle time it saw.
-- gate(now, true) only restarts the clock.
function M.dismissGate(t0)
  local last = t0
  return function(now, ignore)
    local idle = now - last
    last = now
    return not ignore and idle >= PAUSE, idle
  end
end

-- An alarm that fires while the screen is locked or asleep waits behind it:
-- the key or click that wakes the Mac would otherwise count as "after a
-- pause" and close it before Matt sees it. Input then never dismisses, and
-- the pause clock restarts on wake/unlock.
local away = (hs.caffeinate.sessionProperties() or {}).CGSSessionScreenIsLocked == true
local gate = nil
M.lockWatcher = hs.caffeinate.watcher.new(function(ev)
  local w = hs.caffeinate.watcher
  if ev == w.screensDidLock or ev == w.screensDidSleep or ev == w.systemWillSleep then
    away = true
    if resolve then M.dismissResolve("screen locked") end
  elseif ev == w.screensDidUnlock or (ev == w.screensDidWake and not (hs.caffeinate.sessionProperties() or {}).CGSSessionScreenIsLocked) then
    away = false
    if gate then gate(hs.timer.secondsSinceEpoch(), true) end
  end
end):start()

function M.fire(title, body)
  dismiss("replaced")
  local text = title .. (body ~= "" and ("\n" .. body) or "") .. "\n\n(stop typing, then any key or click to dismiss)"
  local style = { textSize = 40, radius = 18, fillColor = { red = 0.75, green = 0.1, blue = 0.1, alpha = 0.92 },
    strokeColor = { white = 1, alpha = 0.9 }, strokeWidth = 4, fadeInDuration = 0.1 }
  for _, scr in ipairs(hs.screen.allScreens()) do
    shown[#shown + 1] = hs.alert.show(text, style, scr, true)
  end

  local out = hs.audiodevice.defaultOutputDevice()
  local played = { ring(out) }
  local spk = builtinSpeakers()
  if spk and (not out or (spk:uid() ~= out:uid() and not worn(out))) then played[#played + 1] = ring(spk) end
  log(string.format("fired %q %q; sound on %s", title, body, table.concat(played, ", ")))

  -- Keys and clicks that keep coming (he is typing) pass through; the first
  -- one after a PAUSE closes it. The tap never swallows the event.
  gate = M.dismissGate(hs.timer.secondsSinceEpoch())
  dismissTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.rightMouseDown }, function()
    local ok, idle = gate(hs.timer.secondsSinceEpoch(), away)
    if ok then dismiss(string.format("key/click after %.1f s pause", idle)) end
    return false
  end)
  dismissTap:start()
  autoClose = hs.timer.doAfter(AUTO_CLOSE, function() dismiss("15 min timeout") end)
end

function M.dismissResolve(why)
  local r = resolve
  if not r then return end
  resolve = nil
  log("resolve dismissed (" .. tostring(why or "api") .. ")")
  if r.tap then r.tap:stop() end
  if r.ticker then r.ticker:stop() end
  if r.autoClose then r.autoClose:stop() end
  for _, c in ipairs(r.canvases) do c:delete(0.3) end
end

local PURPLE = { red = 0.38, green = 0.12, blue = 0.72 }

local function resolveText(r)
  local left = r.deadline - hs.timer.secondsSinceEpoch()
  if r.phase == "grace" then
    return string.format("%s\n\nFinish your sentence. Stopping in %d s.", r.title, math.max(0, math.ceil(left)))
  elseif r.phase == "breath" then
    return string.format("STOP. Take a breath.\n\n%s\nWhat were you working on? Did it resolve?\n\n%d", r.title, math.max(0, math.ceil(left)))
  end
  return string.format("%s\n\nWhat were you working on? Did it resolve?\nWhat is the next cycle for?\n\nPress Return to go back to work.", r.title)
end

local function resolveRedraw(r)
  local alpha = r.phase == "grace" and 0.55 or 0.96
  for _, c in ipairs(r.canvases) do
    c[1].fillColor = { red = PURPLE.red, green = PURPLE.green, blue = PURPLE.blue, alpha = alpha }
    c[2].text = resolveText(r)
  end
end

-- The tap callback: true swallows the event. Input passes in the grace
-- phase and while the screen is locked; Return ends the "done" phase.
function M.resolveFilter(ev)
  local r = resolve
  if not r or r.phase == "grace" or away then return false end
  if r.phase == "done" and ev:getType() == hs.eventtap.event.types.keyDown
    and RETURN_KEYS[ev:getKeyCode()] then
    hs.timer.doAfter(0, function() M.dismissResolve("return") end)
  end
  return true
end

function M.resolveState() return resolve and resolve.phase, resolve and #resolve.canvases end

function M.fireResolve(title, body)
  M.dismissResolve("replaced")
  local r = { canvases = {}, title = title, phase = "grace", deadline = hs.timer.secondsSinceEpoch() + M.GRACE }
  for _, scr in ipairs(hs.screen.allScreens()) do
    local f = scr:fullFrame()
    local c = hs.canvas.new(f):level(hs.canvas.windowLevels.screenSaver)
      :behavior({ "canJoinAllSpaces", "stationary" })
    c[1] = { type = "rectangle", action = "fill", fillColor = PURPLE }
    c[2] = { type = "text", text = "", textSize = 54, textColor = { white = 1 }, textAlignment = "center",
      frame = { x = "8%", y = "28%", w = "84%", h = "60%" } }
    c:show(0.15)
    r.canvases[#r.canvases + 1] = c
  end
  resolve = r
  resolveRedraw(r)

  local out = hs.audiodevice.defaultOutputDevice()
  local played = { ring(out) }
  local spk = builtinSpeakers()
  if spk and (not out or (spk:uid() ~= out:uid() and not worn(out))) then played[#played + 1] = ring(spk) end
  log(string.format("resolve fired %q %q; sound on %s", title, body, table.concat(played, ", ")))

  r.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.rightMouseDown, hs.eventtap.event.types.otherMouseDown,
    hs.eventtap.event.types.scrollWheel }, M.resolveFilter)
  r.tap:start()
  r.ticker = hs.timer.doEvery(1, function()
    if resolve ~= r then return end
    if r.phase ~= "done" and hs.timer.secondsSinceEpoch() >= r.deadline then
      if r.phase == "grace" then
        r.phase, r.deadline = "breath", hs.timer.secondsSinceEpoch() + M.BREATH
        ring(hs.audiodevice.defaultOutputDevice())
        log("resolve: input blocked for " .. M.BREATH .. " s")
      else
        r.phase = "done"
      end
    end
    if r.tap and not r.tap:isEnabled() then r.tap:start() end
    resolveRedraw(r)
  end)
  r.autoClose = hs.timer.doAfter(AUTO_CLOSE, function() M.dismissResolve("15 min timeout") end)
end

hs.urlevent.bind("leader-timer-done", function(_, params)
  local fire = params.kind == "resolve" and M.fireResolve or M.fire
  local ok, err = pcall(fire, params.title or "⏱ Timer done", params.body or "")
  if not ok then log("error: " .. tostring(err)) end
end)

M.dismiss = dismiss
return M
