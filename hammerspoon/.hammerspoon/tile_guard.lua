-- tile_guard.lua — keep Dia's real browser windows in AeroSpace's tiling layer.
--
-- Dia window 1528 was found floating twice on 2026-09-13 (Oops 20260913-154056
-- and -155858), and once more after it had been re-tiled at 15:46, with no
-- alt-space, no alt-shift-t and no Claude command in between. A floating Dia
-- makes every other window on workspace 1 open full-screen underneath it:
-- "the tiling window manager is not tiling". Known ways in: the untitled-window
-- float rule in aerospace.nix (Dia windows created before their title is set),
-- AeroSpace/Tahoe floating Chromium windows (AeroSpace issue #1771), and hotkeys.
--
-- Rule: whenever a Dia window is focused, created or retitled, any Dia window
-- that is floating, is an AXStandardWindow, has a "<Profile>: <page>" title and
-- is at least 500x400 is put back with `aerospace layout tiling`. Popups and
-- toasts (untitled, small, or no profile prefix) are left alone. A window whose
-- last line in ~/.local/state/aerospace-float.log is a deliberate float
-- (alt-space / float-open) is left alone too. Every re-tile is appended to
-- that log with the source "tile-guard", so the next occurrence is dated.

local M = {}

local AEROSPACE = "/opt/homebrew/bin/aerospace"
local FLOATLOG = os.getenv("HOME") .. "/.local/state/aerospace-float.log"

-- Last layout Matt chose for this window by hotkey, or nil.
local function lastIntent(id)
  local f = io.open(FLOATLOG, "r")
  if not f then return nil end
  local last
  for line in f:lines() do
    local wid, layout, source = line:match("^%d+ %S+ %S+ (%d+) (%S+) (%S+)")
    if tonumber(wid) == id and source ~= "tile-guard" then last = layout end
  end
  f:close()
  return last
end

local function logRetile(id, title)
  local f = io.open(FLOATLOG, "a")
  if f then
    f:write(string.format("%d %s %d tiling tile-guard Dia | %s\n",
      os.time(), os.date("%Y-%m-%d %H:%M:%S"), id, title))
    f:close()
  end
end

local function isBrowserWindow(win)
  local title = win:title() or ""
  local fr = win:frame()
  return win:subrole() == "AXStandardWindow"
    and title:match("^[^:|]+: ") ~= nil
    and fr.w >= 500 and fr.h >= 400
end

local busy = false
function M.check()
  if busy then return end
  busy = true
  hs.task.new(AEROSPACE, function(code, out)
    busy = false
    if code ~= 0 then return end
    for line in (out or ""):gmatch("[^\n]+") do
      local id, layout = line:match("^(%d+)|(%S+)")
      id = tonumber(id)
      if id and layout == "floating" and lastIntent(id) ~= "floating" then
        local win = hs.window.get(id)
        if win and isBrowserWindow(win) then
          local title = win:title()
          hs.task.new(AEROSPACE, function(c)
            if c == 0 then logRetile(id, title) end
          end, { "layout", "tiling", "--window-id", tostring(id) }):start()
        end
      end
    end
  end, { "list-windows", "--monitor", "all", "--app-bundle-id", "company.thebrowser.dia",
         "--format", "%{window-id}|%{window-layout}" }):start()
end

-- A new window gets its title a moment after it appears; look again after 2 s.
local function soon() hs.timer.doAfter(2, M.check) end

M.filter = hs.window.filter.new(false):setAppFilter("Dia", { allowRoles = "*" })
M.filter:subscribe(hs.window.filter.windowFocused, M.check)
M.filter:subscribe(hs.window.filter.windowTitleChanged, M.check)
M.filter:subscribe(hs.window.filter.windowCreated, soon)

return M
