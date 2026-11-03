-- alt-Q closes the window under the pointer, not just the focused one.
-- Added 2026-09-14 (Oops 20260914-145958).
--
-- AeroSpace's `alt-q = 'close'` always closed AeroSpace's focused window. A
-- workspace switch moves focus but leaves the pointer where it was, so Matt
-- pointed at the Calendly tile, pressed alt-Q, and lost the focused Google
-- Calendar tile beside it. The binding was removed from aerospace.nix and
-- lives here: close the window under the pointer; if the
-- pointer is over no window (bar, desktop), fall back to `aerospace close`,
-- the old behaviour. Every press is logged to ~/.local/state/hover-close.log.
local M = {}

local LOG = os.getenv("HOME") .. "/.local/state/hover-close.log"
local AEROSPACE = "/opt/homebrew/bin/aerospace"

local systemWide = hs.axuielement.systemWideElement()
-- Don't let one unresponsive app hang Hammerspoon for the default 6 s.
systemWide:setTimeout(1)

local function log(msg)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. msg .. "\n"); f:close() end
end

local function describe(win)
  if not win then return "nil" end
  local app = win:application()
  return string.format("%s — %s [%s]", app and app:name() or "?", win:title() or "", tostring(win:id()))
end

local function screenAt(pt)
  for _, s in ipairs(hs.screen.allScreens()) do
    if pt:inside(s:fullFrame()) then return s end
  end
end

-- Frontmost window at `pt`, using the WindowServer's own hit-test, so the
-- window Matt can see under the pointer is what gets closed.
-- Returns win, or nil plus "none" (no window there: bar, desktop, a window
-- AeroSpace parked in a corner) or "unknown: <err>" (the hit-test failed).
--
-- It used to walk hs.window.orderedWindows() for the first frame containing
-- the pointer. That list is built by asking every app over Accessibility, and
-- an app that doesn't answer (paused by macOS when memory ran out) just drops
-- out, so the window BEHIND it was closed instead: pointer on a paused kitty,
-- Dia's "Hiring Resources" doc closed (Oops 20260915-103107).
function M.windowAt(pt)
  local screen = screenAt(pt)
  if not screen then return nil, "none" end
  local el, err = systemWide:elementAtPosition(pt.x, pt.y)
  if not el then return nil, "unknown: " .. tostring(err) end
  local axwin = (el.AXRole == "AXWindow") and el or el.AXWindow
  if not axwin then return nil, "none" end
  local win = axwin:asHSWindow()
  if not win then return nil, "unknown: no hs.window for " .. tostring(axwin.AXTitle) end
  -- AeroSpace parks windows of hidden workspaces in a screen corner at full
  -- size with a sliver on screen; the pointer in that sliver must not close them.
  if not win:frame().center:inside(screen:fullFrame()) then return nil, "none" end
  return win
end

function M.closeAt(pt)
  pt = pt or hs.mouse.absolutePosition()
  pt = hs.geometry.point(pt.x, pt.y)
  local win, why = M.windowAt(pt)
  -- %.0f, not %d: the pointer position is often fractional (e.g. 980.5), and
  -- %d throws on non-integer floats, which aborted the close (Oops 20260914-162809).
  if win then
    log(string.format("mouse %.0f,%.0f  closing under pointer: %s", pt.x, pt.y, describe(win)))
    win:close()
  elseif why == "none" then
    log(string.format("mouse %.0f,%.0f  no window under pointer -> aerospace close", pt.x, pt.y))
    hs.task.new(AEROSPACE, nil, { "close" }):start()
  else
    -- Don't guess: closing the focused or a lower window is the bug this avoids.
    log(string.format("mouse %.0f,%.0f  NOT closing, %s", pt.x, pt.y, why))
    hs.alert.show("⌥Q: can't tell which window is under the pointer (app not responding?). Nothing closed.")
  end
  return win
end

M.hotkey = hs.hotkey.bind({ "alt" }, "Q", function() M.closeAt() end)

return M
