-- brightness_blackout.lua — brightness 0 on the Mac really means dark, on both screens.
--
-- Added 2026-09-14 (Oops 20260914-112258). Reworked 2026-09-19 (overlays instead
-- of gamma, Oops 20260919-113412). REWRITTEN 2026-09-21 (Oops 20260921-091206),
-- the third report of the same symptom.
--
-- WHY THE REWRITE. Until now the ONLY thing that could start a blackout was an
-- hs.eventtap on systemDefined BRIGHTNESS_UP/DOWN. That tap does not see the way
-- Matt actually changes brightness: at the 09-21 trigger the built-in had been
-- driven to 0 twice (unified log: 09:11:54 and 09:13:00, smooth key-repeat ramps
-- 0.52 -> 0 and 0.60 -> 0) and yet this module's `level` was still nil and
-- `active` still false — i.e. the tap had not fired once in the 38 h since
-- Hammerspoon started. Calling check() by hand blacked both screens correctly,
-- so the mechanism was fine and only the trigger was dead. Both earlier fixes
-- were "verified" by POSTING synthetic systemDefined events, which reach a tap
-- by construction, and both entries recorded "NOT exercised: a physical press".
--
-- So the trigger is now STATE-driven, not event-driven: a timer reads the
-- built-in level and reacts to what it IS, never to what caused it. That covers
-- every path at once — the keys, whichever layer eats them, the Control Center
-- slider (explicitly unsupported before), BetterDisplay, auto-brightness, a
-- script. The event tap is kept only as a 0 s fast path, and it logs when it
-- fires so the next session can see whether it ever does.
--
-- The level comes from hs.brightness.get() (0-100). The old header claimed that
-- returns nothing useful on Apple Silicon; that is no longer true and was
-- re-checked here — with DisplayServicesSetBrightness at 0.5 it returned 50, and
-- at 0.0 it returned 0. Reading it in-process also drops the per-poll
-- /usr/bin/python3 spawn the old check() needed.
--
-- At 0: every screen gets a black overlay and the DELL's DDC luminance goes to 0
-- (m1ddc). Anything above 0 removes the overlays and restores the luminance.

local M = {}

local HOME = os.getenv("HOME")
local M1DDC = HOME .. "/.local/bin/m1ddc"
local SAVED = HOME .. "/.local/state/brightness-blackout-luminance"
local LOG = HOME .. "/.local/state/brightness-blackout.log"

-- macOS's own brightness ramp takes ~0.5 s, so this keeps up with a key press
-- while costing one in-process read per tick.
local POLL = 0.5

M.active = false

local function log(fmt, ...)
  local fh = io.open(LOG, "a")
  if not fh then return end
  fh:write(os.date("%Y-%m-%d %H:%M:%S ") .. string.format(fmt, ...) .. "\n")
  fh:close()
end
M.log = log

local function readFile(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local s = fh:read("*a"); fh:close()
  return s
end

-- Defensive: hs.task.new returns nil if the binary is missing, and indexing
-- that nil inside the poll callback would kill the timer (see tick, below).
-- m1ddc also just fails while the DELL is in standby; that is normal, and
-- M.reapply re-applies luminance 0 when it comes back.
local function ddc(args, cb)
  local t = hs.task.new(M1DDC, function(code, out) if cb then cb(code, out) end end, args)
  if not t then log("m1ddc missing at %s", M1DDC); return end
  t:start()
end

-- A black, click-through canvas over every screen. Not gamma: f.lux (running
-- here) rewrites every display's gamma table within ~1 s, so a black gamma
-- lasted "a split second" (Oops 20260919-113412).
M.overlays = {}

local function removeOverlays()
  for _, c in ipairs(M.overlays) do c:delete() end
  M.overlays = {}
end

local function blackOverlays()
  removeOverlays()
  for _, s in ipairs(hs.screen.allScreens()) do
    local c = hs.canvas.new(s:fullFrame())
    c:appendElements({ type = "rectangle", action = "fill", fillColor = { black = 1, alpha = 1 } })
    c:level(hs.canvas.windowLevels.screenSaver)
    c:behavior({ "canJoinAllSpaces", "stationary" })
    c:show()
    table.insert(M.overlays, c)
  end
end

function M.blackout()
  blackOverlays() -- rebuilt every time, so a screen added since is covered too
  if M.active then return end
  M.active = true
  log("blackout (level=%s)", tostring(M.level))
  if readFile(SAVED) then -- still holding the pre-blackout level (e.g. after a reload)
    ddc({ "set", "luminance", "0" })
    return
  end
  ddc({ "get", "luminance" }, function(code, out)
    local lum = code == 0 and tonumber((out or ""):match("%d+"))
    if lum then
      local fh = io.open(SAVED, "w")
      if fh then fh:write(tostring(lum)); fh:close() end
    end
    ddc({ "set", "luminance", "0" })
  end)
end

function M.restore()
  local was = M.active
  M.active = false
  removeOverlays()
  local lum = tonumber((readFile(SAVED) or ""):match("%d+"))
  if was or lum then log("restore (level=%s luminance=%s)", tostring(M.level), tostring(lum)) end
  if lum then
    ddc({ "set", "luminance", tostring(lum) }, function(code)
      if code == 0 then os.remove(SAVED) end
    end)
  end
end

-- The built-in level as a 0..1 fraction, or nil when there is no built-in screen
-- (lid closed: there is no Mac brightness to follow, and reading 0 there would
-- black out the external for no reason).
function M.level0()
  local builtin
  for _, s in ipairs(hs.screen.allScreens()) do
    if s:name():match("^Built%-in") then builtin = s end
  end
  if not builtin then return nil end
  local pct = hs.brightness.get()
  if type(pct) ~= "number" or pct < 0 then return nil end
  return pct / 100
end

-- Reacts to the level itself, so it does not care what changed it.
function M.check()
  local level = M.level0()
  if not level then return end
  M.level = level
  if level <= 0.001 then
    M.blackout()
  elseif M.active or readFile(SAVED) then
    M.restore()
  end
end

-- The poll is wrapped and watchdogged on purpose. A Hammerspoon timer whose
-- callback throws is STOPPED by Hammerspoon, and a stopped poller is silently
-- the whole bug again — the feature looks installed and does nothing. That is
-- not theoretical: it happened once during this session's own testing, with the
-- DELL asleep so the m1ddc task could not run. So: never let an error escape
-- the callback, and have a slower timer put the poller back if it ever dies.
local function tick()
  local ok, err = pcall(M.check)
  if not ok then log("check error: %s", tostring(err)) end
end

M.poller = hs.timer.doEvery(POLL, tick)

M.watchdog = hs.timer.doEvery(30, function()
  if not (M.poller and M.poller:running()) then
    log("poller was not running — restarting it")
    M.poller = hs.timer.doEvery(POLL, tick)
  end
end)

-- Fast path only. If this ever fires, the log line proves the tap is alive on
-- this machine after all; the poller is what the feature actually relies on.
M.tap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(e)
  local d = e:systemKey()
  if d and d.down and (d.key == "BRIGHTNESS_UP" or d.key == "BRIGHTNESS_DOWN") then
    log("tap saw %s", d.key)
    hs.timer.doAfter(0.4, function() M.check() end)
  end
  return false
end)
M.tap:start()

-- Keep it dark: a DELL reconnect or a wake can leave the overlays on the wrong
-- frames and the DELL back at its own luminance, so re-apply both.
function M.reapply()
  if M.active then blackOverlays(); ddc({ "set", "luminance", "0" }) end
end
M.screenWatcher = hs.screen.watcher.new(function() hs.timer.doAfter(2, M.reapply) end):start()
M.wakeWatcher = hs.caffeinate.watcher.new(function(ev)
  if ev == hs.caffeinate.watcher.systemDidWake or ev == hs.caffeinate.watcher.screensDidWake then
    hs.timer.doAfter(3, M.reapply)
  end
end):start()

log("loaded (poll=%ss)", tostring(POLL))

return M
