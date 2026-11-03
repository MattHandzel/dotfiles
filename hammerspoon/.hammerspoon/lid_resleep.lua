-- lid_resleep.lua — a wake nobody asked for, with the lid shut, goes back to sleep.
--
-- Added 2026-10-29 (Oops 20261029-195452). Matt presses ⌥⎋ (AeroSpace
-- `sleep 1 && pmset sleepnow`) and closes the lid while the DELL is plugged in
-- (one USB-C cable = power + display). The lid shut 1 s into the sleep; the
-- Mac finished sleeping with the clamshell closed and woke itself 0.3 s later
-- ("due to NUB.SPMISw3IRQ nub-spmi0.0x02 rtc/Alarm", no HID), then ran in
-- clamshell mode on the DELL. macOS has no setting for this.
--
-- Rule, checked 4 s after every full wake: lid closed AND the wake reason in
-- `pmset -g log` is not a keyboard/mouse/lid one AND nothing was touched since
-- the wake AND sleep is not disabled (lid-awake) → `pmset sleepnow` again.
-- Waking the closed Mac on purpose (a Totem key or the mouse) reports
-- "HID Activity"/"UserActivity" and is left alone. At most 3 re-sleeps per
-- 10 min, so a wake loop can't trap the machine. Log: ~/.local/state/lid-resleep.log

local M = {}

local LOG = os.getenv("HOME") .. "/.local/state/lid-resleep.log"
local USER_WAKE = { "HID Activity", "UserActivity", "User", "trackpadkeyboard", "lid" }

local function log(fmt, ...)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. string.format(fmt, ...) .. "\n"); f:close() end
end

M.recent = {}

local PROBE = [==[
/usr/sbin/ioreg -r -k AppleClamshellState -d 1 | grep -o '"AppleClamshellState" = [A-Za-z]*' | head -1
/usr/bin/pmset -g | grep -o 'SleepDisabled[[:space:]]*[0-9]'
/usr/bin/pmset -g log | grep -E '^[0-9-]+ [0-9:]+ [-+][0-9]{4} Wake ' | tail -1
]==]

-- Pure decision, separated so it can be tested: returns sleep?, why.
function M.decide(out, sinceWake, idle, now)
  local closed = out:match('"AppleClamshellState" = (%a+)') == "Yes"
  if not closed then return false, "lid open" end
  if out:match("SleepDisabled%s*1") then return false, "sleep disabled (lid-awake)" end
  local y, mo, d, h, mi, s, reason =
    out:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+) [-+]%d+ Wake [^\n]-due to ([^\n]*)")
  if not y then return false, "no wake line" end
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  if math.abs(now - t) > 120 then return false, "wake line stale (" .. (now - t) .. " s old)" end
  reason = reason:gsub("%s*Using.*$", "")
  for _, w in ipairs(USER_WAKE) do
    if reason:find(w, 1, true) then return false, "user wake: " .. reason end
  end
  if idle < sinceWake - 1 then return false, "input since wake (idle " .. math.floor(idle) .. " s)" end
  return true, reason
end

function M.check()
  local sinceWake = os.time() - (M.wokeAt or os.time())
  M.task = hs.task.new("/bin/sh", function(_, out)
    local now = os.time()
    local go, why = M.decide(out or "", sinceWake, hs.host.idleTime(), now)
    if not go then log("stay awake: %s", why); return end
    local keep = {}
    for _, t in ipairs(M.recent) do if now - t < 600 then table.insert(keep, t) end end
    M.recent = keep
    if #M.recent >= 3 then log("NOT re-sleeping (3 in 10 min): %s", why); return end
    table.insert(M.recent, now)
    log("lid closed, no user wake (%s) -> pmset sleepnow", why)
    hs.task.new("/usr/bin/pmset", nil, { "sleepnow" }):start()
  end, { "-c", PROBE })
  M.task:start()
end

M.watcher = hs.caffeinate.watcher.new(function(ev)
  if ev == hs.caffeinate.watcher.systemDidWake then
    M.wokeAt = os.time()
    hs.timer.doAfter(4, M.check)
  end
end):start()

return M
