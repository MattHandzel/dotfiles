-- paused_apps.lua — say so the moment macOS leaves an app frozen.
-- Added 2026-09-15 (Oops 20260915-104240).
--
-- At 10:27 the kernel ran out of swap and suspended GUI apps ("memorystatus:
-- suspending Wispr Flow [1152] due to swap exhaustion"). It resumed Dia,
-- Dayflow, Claude and the kittys, but never Wispr Flow. A suspended app does
-- not answer Accessibility, and AeroSpace's refresh waits on every app: each
-- `aerospace` command then takes ~6 s, and newly opened windows are dropped
-- from the layout and come back seconds later. That is what "applications
-- appeared and disappeared" was at 10:42, 15 minutes after the suspension.
-- Reproduced by stalling one app during a real alt-T: the new kitty split
-- workspace 1, vanished at +10 s with focus snapping to Dia, back at +15 s.
--
-- A user process cannot resume it (pid_resume -> "Operation not permitted");
-- only Force Quit's "Resume" (⌘⌥⎋) or quitting the app does. So this module
-- watches the kernel's suspend/resume lines, and if an app is still suspended
-- GRACE seconds later (the kernel often resumes on its own within seconds),
-- shows a sticky alert naming it. Log: ~/.local/state/paused-apps.log.
local M = {}

M.GRACE = 20

local LOG = os.getenv("HOME") .. "/.local/state/paused-apps.log"

M.suspended = {} -- pid -> { name =, t = }

local function log(msg)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. msg .. "\n"); f:close() end
end

local function alive(pid)
  return hs.execute("/bin/kill -0 " .. pid .. " 2>/dev/null && echo y"):match("y") ~= nil
end

local function stillSuspended()
  local list = {}
  for pid, s in pairs(M.suspended) do
    if not alive(pid) then
      M.suspended[pid] = nil
    elseif os.time() - s.t >= M.GRACE then
      list[#list + 1] = string.format("%s [%d]", s.name, pid)
    end
  end
  table.sort(list)
  return list
end

function M.refreshAlert()
  if M.alert then hs.alert.closeSpecific(M.alert); M.alert = nil end
  local list = stillSuspended()
  if #list == 0 then return end
  local text = "macOS paused (out of memory): " .. table.concat(list, ", ")
    .. "\nWindows will jump around until it runs again: ⌘⌥⎋ → select it → Resume, or quit it."
  log("ALERT " .. table.concat(list, ", "))
  M.alert = hs.alert.show(text, { textSize = 16 }, hs.screen.mainScreen(), 1e6)
end

-- One kernel log line. Returns "suspend"/"resume"/nil (used by tests too).
function M.feed(line)
  local name, pid = line:match("memorystatus: suspending (.-) %[(%d+)%] due to")
  if name then
    pid = tonumber(pid)
    M.suspended[pid] = { name = name, t = os.time() }
    log(string.format("suspended %s [%d]", name, pid))
    hs.timer.doAfter(M.GRACE + 1, M.refreshAlert)
    return "suspend"
  end
  name, pid = line:match("memorystatus: resuming (.-) %[(%d+)%]")
  if name then
    pid = tonumber(pid)
    if M.suspended[pid] then log(string.format("resumed %s [%d]", name, pid)) end
    M.suspended[pid] = nil
    M.refreshAlert()
    return "resume"
  end
end

local buf = ""
function M.start(predicate)
  local old = M.task
  M.task = nil
  if old then old:terminate() end
  predicate = predicate or 'process == "kernel" AND (eventMessage BEGINSWITH "memorystatus: suspending" OR eventMessage BEGINSWITH "memorystatus: resuming")'
  local task
  task = hs.task.new("/usr/bin/log", function(code)
    if M.task ~= task then return end -- replaced by a later start(), not a crash
    log("log stream exited " .. tostring(code) .. ", restarting in 10 s")
    hs.timer.doAfter(10, function() if M.task == task then M.start() end end)
  end, function(_, out)
    buf = buf .. (out or "")
    while true do
      local nl = buf:find("\n")
      if not nl then break end
      local line = buf:sub(1, nl - 1)
      buf = buf:sub(nl + 1)
      if M.onLine then M.onLine(line) end
      M.feed(line)
    end
    return true
  end, { "stream", "--style", "compact", "--predicate", predicate })
  M.task = task
  task:start()
end

-- A dead app, or one resumed without a kernel line we saw (e.g. before a reload),
-- must not keep the alert up.
M.sweep = hs.timer.doEvery(30, function()
  if next(M.suspended) == nil then return end
  for pid in pairs(M.suspended) do
    local app = hs.application.applicationForPID(pid)
    if app then
      local ax = hs.axuielement.applicationElement(app)
      if ax then
        ax:setTimeout(1)
        if ax:attributeValue("AXRole") ~= nil then
          log(string.format("answers AX again: %s [%d]", M.suspended[pid].name, pid))
          M.suspended[pid] = nil
        end
      end
    end
  end
  M.refreshAlert()
end)

M.start()

return M
