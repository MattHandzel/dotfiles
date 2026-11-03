-- Screen recording toggle — the macOS twin of the Linux `record screen`
-- (wf-recorder) Vicinae command. Added 2026-09-13 (Oops 20260913-171439:
-- Raycast "record" / "screen rec" found nothing).
--
-- Lives in Hammerspoon, not in the Raycast script itself, because Hammerspoon
-- already holds the Screen Recording (TCC) grant; a screencapture spawned by
-- Raycast or launchd would be attributed to that parent instead. Reached via
--   open -g hammerspoon://screen-record     (Raycast "Record Screen (toggle)")
-- First call starts `screencapture -v` on the main display, the second sends it
-- SIGINT, which finalises the .mov. Output: ~/Videos/<timestamp>.mov.
local M = {}

local DIR = os.getenv("HOME") .. "/Videos"

M.task = nil
M.path = nil

local function notify(title, text, path)
  local n = hs.notify.new(function()
    if path then hs.execute("/usr/bin/open -R " .. string.format("%q", path)) end
  end, { title = title, informativeText = text, withdrawAfter = 8 })
  n:send()
end

function M.start()
  if M.task and M.task:isRunning() then return M.path end
  hs.fs.mkdir(DIR)
  M.path = DIR .. "/" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".mov"
  local path = M.path
  M.task = hs.task.new("/usr/sbin/screencapture", function(code, _, err)
    M.task = nil
    local size = hs.fs.attributes(path, "size")
    if size and size > 0 then
      hs.pasteboard.setContents(path)
      notify("Screen recording saved", path .. " (path copied; click to reveal)", path)
    else
      notify("Screen recording failed", "exit " .. tostring(code) .. " " .. (err or ""))
    end
  end, { "-v", "-k", "-x", path })
  if not M.task:start() then
    M.task = nil
    notify("Screen recording failed", "could not start screencapture")
    return nil
  end
  hs.alert.show("● recording screen — run Record Screen again to stop", 1.5)
  return path
end

function M.stop()
  if not (M.task and M.task:isRunning()) then return false end
  M.task:interrupt()
  hs.alert.show("■ recording stopped", 0.8)
  return true
end

function M.toggle()
  if M.task and M.task:isRunning() then M.stop() else M.start() end
end

hs.urlevent.bind("screen-record", function(_, params)
  if params.action == "stop" then M.stop()
  elseif params.action == "start" then M.start()
  else M.toggle() end
end)

return M
