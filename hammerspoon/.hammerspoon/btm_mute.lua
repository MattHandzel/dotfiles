-- Auto-dismiss macOS "App Background Activity — “sh” can run in the background"
-- banners. Added 2026-09-13 (Oops 20260913-125648).
--
-- backgroundtaskmanagementd posts one advisory for every NEW launch agent
-- label. Every home-manager agent runs `/bin/sh -c …`, so each hm activation
-- that adds an agent pops a banner named “sh”. There is no per-user switch:
-- notification settings live in the TCC-locked group.com.apple.usernoted
-- container, and the managed-login-items profile needs admin/MDM. So close the
-- banner the moment Notification Center draws it. Only banners whose text
-- contains BTM_TEXT are touched; everything else is left alone.
local ax = require("hs.axuielement")

local M = {}

local NC_BUNDLE = "com.apple.notificationcenterui"
local BTM_TEXT = "can run in the background"
local LOG = os.getenv("HOME") .. "/.local/state/btm-mute.log"
local ALERT_SUBROLES = { AXNotificationCenterAlert = true, AXNotificationCenterAlertStack = true }

local function log(msg)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. msg .. "\n"); f:close() end
end

local function textOf(el, depth, acc)
  if not el or depth > 8 then return acc end
  for _, attr in ipairs({ "AXValue", "AXDescription", "AXTitle" }) do
    local ok, v = pcall(function() return el:attributeValue(attr) end)
    if ok and type(v) == "string" and v ~= "" then acc[#acc + 1] = v end
  end
  local ok, kids = pcall(function() return el:attributeValue("AXChildren") end)
  for _, kid in ipairs(ok and kids or {}) do textOf(kid, depth + 1, acc) end
  return acc
end

local function closeAction(el)
  for _, name in ipairs(el:actionNames() or {}) do
    if string.find(string.lower(tostring(name)), "close", 1, true) then return name end
  end
end

-- How long one sweep may spend walking NC's AX tree, in seconds.
--
-- Added 2026-09-21 (Oops 20260921-091206). This walk does four SYNCHRONOUS AX
-- round-trips per node on Hammerspoon's MAIN THREAD, and it used to run every
-- 5 s with no bound at all. Measured here: `AXWindows` on Notification Center
-- returns the whole application element three times over, each ~3000+ nodes at
-- depth 6 alone, so one sweep was tens of thousands of round-trips and parked
-- the main thread for MINUTES. While it is parked EVERY Hammerspoon event tap
-- is deaf — that is what cost Matt the brightness blackout (the key press never
-- reached the tap) and what put a 14 s hole in that incident's own keys.log.
--
-- Two budgets, because the two callers are not alike. BURST runs only when the
-- AX observer says NC actually created something, i.e. when there really may be
-- a banner to close, so it gets room to find one. IDLE is the blind backstop;
-- it is the one that used to run forever for nothing.
local BUDGET_BURST = 1.5
local BUDGET_IDLE = 0.3

-- Walk NC's windows; close every single alert whose text mentions BTM_TEXT.
function M.sweep(budget)
  local app = hs.application.get(NC_BUNDLE)
  if not app then return 0 end
  local closed = 0
  local deadline = hs.timer.secondsSinceEpoch() + (budget or BUDGET_IDLE)
  local function walk(el, depth)
    if not el or depth > 10 then return end
    if hs.timer.secondsSinceEpoch() > deadline then return end
    local ok, sub = pcall(function() return el:attributeValue("AXSubrole") end)
    if ok and sub and ALERT_SUBROLES[sub] then
      local text = table.concat(textOf(el, 0, {}), " | ")
      if string.find(text, BTM_TEXT, 1, true) then
        local action = closeAction(el)
        if action then
          pcall(function() el:performAction(action) end)
          closed = closed + 1
          log("closed: " .. text)
        else
          log("no close action (" .. sub .. "): " .. text)
        end
      end
      return
    end
    local okk, kids = pcall(function() return el:attributeValue("AXChildren") end)
    for _, kid in ipairs(okk and kids or {}) do walk(kid, depth + 1) end
  end
  local okw, wins = pcall(function() return ax.applicationElement(app):attributeValue("AXWindows") end)
  -- On macOS 26 this list comes back as the same application element repeated
  -- once per window, so walking it naively re-walks the identical tree three
  -- times. Dedupe first; it is a straight 3x saving with nothing given up.
  local seen = {}
  for _, win in ipairs((okw and wins) or {}) do
    if hs.timer.secondsSinceEpoch() > deadline then break end
    local key = tostring(win)
    if not seen[key] then
      seen[key] = true
      walk(win, 0)
    end
  end
  if hs.timer.secondsSinceEpoch() > deadline then log("sweep gave up at its budget") end
  return closed
end

-- Banners animate in; sweep a few times after NC reports a new window/element.
local function burst()
  for _, delay in ipairs({ 0.3, 1.0, 2.5 }) do
    hs.timer.doAfter(delay, function() M.sweep(BUDGET_BURST) end)
  end
end

local function attach()
  if M.observer then M.observer:stop(); M.observer = nil end
  local app = hs.application.get(NC_BUNDLE)
  if not app then return end
  local obs = ax.observer.new(app:pid())
  obs:callback(function() burst() end)
  local appEl = ax.applicationElement(app)
  obs:addWatcher(appEl, "AXWindowCreated")
  obs:addWatcher(appEl, "AXCreated")
  obs:start()
  M.observer = obs
end

attach()
-- Notification Center restarts (crash, logout helpers) get a new pid.
M.appWatcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.launched and app and app:bundleID() == NC_BUNDLE then
    hs.timer.doAfter(1, attach)
  end
end)
M.appWatcher:start()
-- Backstop in case an AX notification is missed. 60 s, not the old 5 s: the
-- observer above is the real trigger, and this blind walk is pure cost every
-- time it runs. At 5 s it stalled the main thread ~6% of the time even with a
-- budget; at 60 s the worst case is 0.3 s a minute (2026-09-21 Oops).
M.timer = hs.timer.doEvery(60, function() M.sweep(BUDGET_IDLE) end)

return M
