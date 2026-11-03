-- hl_guard.lua — Cmd+H / Cmd+L do nothing when there is nowhere to move.
--
-- Added 2026-10-06 (Oops 20261006-200102). Matt's "move left/right" habit is
-- h/l with Command: in kitty, Cmd+H/L are tmux/nvim pane left/right
-- (modules/home/kitty.nix). Outside kitty the same chord is a macOS app
-- shortcut instead: Cmd+H hides the app, and because AeroSpace runs with
-- automatically-unhide-macos-hidden-apps = true the hide is undone at once,
-- so all it does is jump to another workspace and straight back. In Dia,
-- Cmd+L throws focus into the address bar. Matt asked that with one window on
-- the workspace and no second monitor, h and l "don't move me around".
--
-- So: Cmd+H / Cmd+L (no other modifier) outside kitty are swallowed when the
-- focused AeroSpace workspace holds at most one window AND only one display is
-- connected. In every other case they pass through untouched. Option+H/L are
-- AeroSpace's own `focus --boundaries all-monitors-outer-frame` bindings and
-- already stop at the edge in that situation; this tap does not touch them.
--
-- The window count is a synchronous AeroSpace CLI call (~15 ms), capped at
-- 0.3 s so a hung AeroSpace cannot park Hammerspoon's main thread; any error
-- or timeout lets the key through.

local M = {}

local AEROSPACE = "/opt/homebrew/bin/aerospace"
local TIMEOUT = "/run/current-system/sw/bin/timeout"
local EXCLUDED = { ["net.kovidgoyal.kitty"] = true }
local KEYS = { [hs.keycodes.map.h] = "h", [hs.keycodes.map.l] = "l" }

local function windowsOnFocusedWorkspace()
  local p = io.popen(TIMEOUT .. " 0.3 " .. AEROSPACE .. " list-windows --workspace focused --count 2>/dev/null")
  if not p then return nil end
  local out = p:read("*a")
  p:close()
  return tonumber(out and out:match("%d+"))
end

-- Pure decision, kept separate so it can be tested without a live tap.
function M.shouldSwallow(key, flags, bundleID, screens, windows)
  if not key then return false end
  if not flags.cmd or flags.alt or flags.ctrl or flags.shift or flags.fn then return false end
  if bundleID and EXCLUDED[bundleID] then return false end
  if screens ~= 1 then return false end
  return windows ~= nil and windows <= 1
end

M.windows = windowsOnFocusedWorkspace

function M.onKeyDown(e)
  local key = KEYS[e:getKeyCode()]
  if not key then return false end
  local f = e:getFlags()
  if not f.cmd or f.alt or f.ctrl or f.shift or f.fn then return false end
  local ok, swallow = pcall(function()
    local app = hs.application.frontmostApplication()
    local bundleID = app and app:bundleID()
    if bundleID and EXCLUDED[bundleID] then return false end
    local screens = #hs.screen.allScreens()
    if screens ~= 1 then return false end
    return M.shouldSwallow(key, f, bundleID, screens, windowsOnFocusedWorkspace())
  end)
  if ok and swallow then
    -- A swallowed key may never reach the Oops recorder; this line still does.
    print("hl_guard: swallowed cmd-" .. key .. " (one window, one display)")
    return true
  end
  return false
end

M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, M.onKeyDown)
M.tap:start()

return M
