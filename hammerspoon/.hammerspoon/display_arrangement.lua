-- display_arrangement.lua — keep the secondary display stacked ABOVE the built-in.
--
-- Added 2026-09-20 (Oops 20260920-120528; first asked 2026-09-14). The
-- arrangement is WindowServer state, not something the flake can declare, and
-- the WindowServer plist still holds an older "DELL above" entry that had since
-- reverted to side-by-side — so setting it once is not enough. The applier is
-- ~/.local/bin/display-stack-secondary (modules/home/darwin/display-arrangement.nix),
-- which is idempotent and also runs at login from a launchd agent.
--
-- Stacked above is what makes AeroSpace's alt-k / alt-j the keys that cross
-- between monitors instead of alt-l / alt-h.
--
-- Fires only when WHICH screens are connected changes, and at 2 s — ahead of
-- monitor_mode.lua's 3 s — because AeroSpace numbers monitors by position, so
-- the arrangement must settle before workspaces are spread over them.

local M = {}

local APPLY = os.getenv("HOME") .. "/.local/bin/display-stack-secondary"

local function screenSet()
  local ids = {}
  for _, s in ipairs(hs.screen.allScreens()) do table.insert(ids, s:getUUID()) end
  table.sort(ids)
  return table.concat(ids, ",")
end

M.last = screenSet()

M.timer = hs.timer.delayed.new(2, function()
  local now = screenSet()
  if now == M.last then return end
  M.last = now
  hs.task.new(APPLY, nil):start()
end)

M.watcher = hs.screen.watcher.new(function() M.timer:start() end)
M.watcher:start()

return M
