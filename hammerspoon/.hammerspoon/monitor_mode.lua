-- monitor_mode.lua — re-apply the AeroSpace monitor mode when screens change.
--
-- Added 2026-09-14. `monitor-mode` (modules/home/darwin/aerospace-helpers.nix)
-- spreads workspaces over the laptop + external monitor: "single" puts all of
-- them on the external, "split" puts 1-10 on the laptop and 11-20 on the
-- external. AeroSpace dumps every workspace onto the remaining screen when one
-- disappears and never moves them back, so plugging in / opening the lid needs
-- the mode applied again. Raycast "Monitor Mode: ..." sets the mode.
--
-- Only a change in WHICH screens are connected triggers it (not wake, resolution
-- or arrangement changes), so a workspace moved by hand with alt-shift-hjkl
-- stays put until the next plug/unplug.

local M = {}

local MONITOR_MODE = "/etc/profiles/per-user/matth/bin/monitor-mode"

local function screenSet()
  local ids = {}
  for _, s in ipairs(hs.screen.allScreens()) do table.insert(ids, s:getUUID()) end
  table.sort(ids)
  return table.concat(ids, ",")
end

M.last = screenSet()

-- AeroSpace needs a moment to notice the new monitor before workspaces can move.
M.timer = hs.timer.delayed.new(3, function()
  local now = screenSet()
  if now == M.last then return end
  M.last = now
  hs.task.new(MONITOR_MODE, nil, { "apply" }):start()
end)

M.watcher = hs.screen.watcher.new(function() M.timer:start() end)
M.watcher:start()

return M
