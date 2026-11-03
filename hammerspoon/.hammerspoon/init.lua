-- Notification control.
--   alt-Y        dismiss the topmost notification
--   alt-shift-Y  dismiss every notification on screen
--
-- Requires Hammerspoon to hold Accessibility permission.
--
-- REWRITTEN 2026-09-11. macOS 26 broke the previous implementation in two
-- separate ways, and either one alone was enough to make both chords do
-- nothing but flash "no notification":
--
--   1. hs.application.get("NotificationCenter") does not resolve the real
--      process. The app's name is "Notification Center", WITH A SPACE, so that
--      lookup fell through to a stale fuzzy match and handed back a dead pid
--      whose AXWindows list was empty. Match the BUNDLE ID instead, which is
--      stable and unambiguous.
--
--   2. There is no Close button to press any more. The close control is only
--      materialised while the pointer hovers the banner, so walking the tree
--      for an AXButton whose description says "close" found nothing even when
--      notifications were plainly on screen. Notifications now carry CUSTOM
--      actions instead, surfaced through actionNames(), and performing one is
--      the supported way to dismiss.
local ax = require("hs.axuielement")

-- ── GLOBAL ACCESSIBILITY TIMEOUT ────────────────────────────────────────────
-- Added 2026-09-21 (Oops 20260921-091206). EVERY hs.axuielement read is a
-- synchronous mach_msg to the target app, made ON HAMMERSPOON'S MAIN THREAD,
-- and by default it waits forever. One app that stops answering therefore
-- freezes ALL of Hammerspoon: every hotkey, every event tap, `hs -c`, the Oops
-- recorder. That is not hypothetical here — Notification Center did exactly
-- this and cost Matt the brightness blackout (see brightness_blackout.lua) and
-- a 14 s hole in that incident's keys.log, and the same shape burned 41 min on
-- 2026-09-19. Setting the timeout on the systemwide element sets the process
-- default for every element created afterwards, so one line bounds the damage
-- for every module below. Healthy apps answer AX queries in single-digit ms.
ax.systemWideElement():setTimeout(0.5)

local NC_BUNDLE = "com.apple.notificationcenterui"

-- A lone notification and a collapsed stack of them are different subroles.
local ALERT_SUBROLES = {
  AXNotificationCenterAlertStack = true,
  AXNotificationCenterAlert = true,
}

-- Priority order, most specific first. A single alert offers "Close"; a
-- collapsed stack offers only "Clear All", because there is no per-item close
-- control on a stack.
local SINGLE_ACTIONS = { "close", "clear all" }
local ALL_ACTIONS = { "clear all", "close" }

local function alerts()
  local app = hs.application.get(NC_BUNDLE)
  if not app then return {} end
  local axApp = ax.applicationElement(app)
  if not axApp then return {} end
  local out = {}
  -- Depth-limited: the widget windows (Featured/Forecast/Month) hang off the
  -- same app and the calendar one is deep enough to hang the hotkey.
  local function walk(el, depth)
    if not el or depth > 10 then return end
    local ok, sub = pcall(function() return el:attributeValue("AXSubrole") end)
    if ok and sub and ALERT_SUBROLES[sub] then out[#out + 1] = el end
    for _, kid in ipairs(el:attributeValue("AXChildren") or {}) do
      walk(kid, depth + 1)
    end
  end
  for _, win in ipairs(axApp:attributeValue("AXWindows") or {}) do walk(win, 0) end
  return out
end

-- actionNames() returns custom actions as multi-line descriptor strings, e.g.
-- "Name:Clear All\nTarget:0x0\nSelector:(null)", so match on substring rather
-- than equality.
local function actionMatching(el, wanted)
  local names = el:actionNames() or {}
  for _, want in ipairs(wanted) do
    for _, name in ipairs(names) do
      if string.find(string.lower(tostring(name)), want, 1, true) then return name end
    end
  end
  return nil
end

-- Returns how many it dismissed.
local function dismiss(all)
  local closed = 0
  local wanted = all and ALL_ACTIONS or SINGLE_ACTIONS
  for _ = 1, (all and 25 or 1) do
    local list = alerts()
    if #list == 0 then break end
    local acted = false
    for _, el in ipairs(list) do
      local action = actionMatching(el, wanted)
      if action then
        -- The element goes invalid the instant the alert leaves the screen, so
        -- performAction reports an error even when it succeeded. Swallow it.
        pcall(function() el:performAction(action) end)
        closed = closed + 1
        acted = true
        if not all then return closed end
      end
    end
    if not acted then break end
    hs.timer.usleep(200000)
  end
  return closed
end


hs.hotkey.bind({ "alt" }, "Y", function()
  if dismiss(false) == 0 then hs.alert.show("no notification", 0.6) end
end)

hs.hotkey.bind({ "alt", "shift" }, "Y", function()
  local n = dismiss(true)
  hs.alert.show(n > 0 and ("cleared " .. n) or "nothing to clear", 0.6)
end)

hs.alert.show("Hammerspoon ready — alt-Y / alt-shift-Y", 1.2)

-- ── brightness (Hyprland SUPER+XF86MonBrightnessUp/Down) ────────────────────
-- Those Hyprland binds jumped straight to the extremes: Super+Up = 100%,
-- Super+Down = 0%. AeroSpace cannot bind media keys at all, because brightness
-- arrives as a systemDefined event rather than a normal keypress, so this is an
-- event tap instead. Bare brightness keys are untouched and still step normally.
local NX_BRIGHTNESS_UP, NX_BRIGHTNESS_DOWN = 2, 3
local BRIGHTNESS = os.getenv("HOME") .. "/.local/bin/brightness"

brightnessTap = hs.eventtap.new({ hs.eventtap.event.types.systemDefined }, function(e)
  local d = e:systemKey()
  if not d or not d.down then return false end
  if d.key ~= "BRIGHTNESS_UP" and d.key ~= "BRIGHTNESS_DOWN" then return false end
  -- Only intercept when Option or Command is held; a bare tap must behave
  -- normally. Command too (2026-09-18, Oops 20260918-095052): ⌘+Brightness
  -- Down is macOS's "toggle display mirroring", and the Totem's GUI key is ⌘,
  -- so Hyprland's Super+Brightness mirrored the DELL and macOS saved it.
  local f = e:getFlags()
  if not f.alt and not f.cmd then return false end
  local level = (d.key == "BRIGHTNESS_UP") and "100" or "0"
  hs.task.new("/bin/bash", function()
    if brightnessBlackout then brightnessBlackout.check() end
  end, { BRIGHTNESS, "-s", level }):start()
  hs.alert.show("brightness " .. level .. "%", 0.5)
  return true -- swallow it so macOS does not also step the panel
end)
brightnessTap:start()

-- ── browser back/forward on Option+Arrow (Linux muscle memory) ──────────────
-- On Linux, Alt+Left/Right walked browser history. macOS uses Cmd+[ / Cmd+].
-- This translates the Linux chord to the Mac one, but ONLY while a browser is
-- frontmost; everywhere else the keystroke passes through untouched, so it does
-- not shadow Option+Arrow in editors or the terminal.
local BROWSERS = {
  ["app.zen-browser.zen"]        = true,  -- Zen
  ["company.thebrowser.dia"]     = true,  -- Dia (added 2026-09-12, Zen → Dia migration)
  ["com.google.Chrome"]          = true,
  ["com.apple.Safari"]           = true,
  ["com.brave.Browser"]          = true,
}
local LEFT, RIGHT = 123, 124

browserHistoryTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  local code = e:getKeyCode()
  if code ~= LEFT and code ~= RIGHT then return false end
  local f = e:getFlags()
  -- Option alone. Any other modifier (incl. shift, which AeroSpace uses to
  -- resize) must pass straight through.
  if not f.alt or f.cmd or f.ctrl or f.shift or f.fn then return false end
  local app = hs.application.frontmostApplication()
  if not app or not BROWSERS[app:bundleID()] then return false end
  hs.eventtap.keyStroke({ "cmd" }, code == LEFT and "[" or "]", 0, app)
  return true -- swallow the original so the browser does not also see Option+Arrow
end)
browserHistoryTap:start()

-- Added 2026-09-11 for shell-side debugging: enables `hs -c "<lua>"`.
require("hs.ipc")

-- ── Cmd+Delete deletes the previous WORD, not the whole line ─────────────────
-- Added 2026-09-12. karabiner.nix carries the same rewrite, but Karabiner only
-- touches keys on devices it grabs and it never grabs the Totem (deliberately —
-- see the `devices = []` note there). So from the Totem, Cmd+Delete in Google
-- Docs still ate a whole line. An event tap sits after every keyboard driver,
-- so this covers both boards. The event is modified in place and passed on
-- (return false) rather than re-posted, which keeps key-repeat working.
-- Excluded in kitty for the same reasons Karabiner excludes it: Ctrl+W already
-- word-deletes there, and left Command is Control in kitty on the internal
-- keyboard. Shift/Ctrl/Option variants pass through untouched.
local DELETE = 51
local CMD_DELETE_EXCLUDED = { ["net.kovidgoyal.kitty"] = true }

cmdDeleteTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  if e:getKeyCode() ~= DELETE then return false end
  local f = e:getFlags()
  if not f.cmd or f.alt or f.ctrl or f.shift or f.fn then return false end
  local app = hs.application.frontmostApplication()
  if app and CMD_DELETE_EXCLUDED[app:bundleID()] then return false end
  e:setFlags({ alt = true })
  return false -- pass the rewritten event (Option+Delete) on to the app
end)
cmdDeleteTap:start()

-- ── read-aloud floating player (no hotkeys; shown by the Raycast "Read Aloud" command) ──
readAloudPlayer = require("readaloud_player")

-- ── Oops: 90-s keystroke/app/click recorder + "something went wrong" trigger ──
-- Added 2026-09-12. Recorder + trigger in oops.lua; the Claude half is the
-- nix-managed `oops` script (modules/home/darwin/oops.nix). Reached via
-- AeroSpace alt-backtick / Raycast "Oops" -> hammerspoon://oops.
oops = require("oops")

-- ── auto-close "“sh” can run in the background" (BTM) banners ───────────────
-- Added 2026-09-13. Every new home-manager launch agent triggers one; see btm_mute.lua.
btmMute = require("btm_mute")

-- ── keep Dia's browser windows tiled in AeroSpace ────────────────────────────
-- Added 2026-09-13 (Oops 20260913-155858); see tile_guard.lua.
tileGuard = require("tile_guard")

-- ── Bitwarden opens on the workspace you are on ─────────────────────────────
-- Added 2026-09-13 (Oops 20260913-171335); see bitwarden_follow.lua.
bitwardenFollow = require("bitwarden_follow")

-- ── screen recording toggle (Raycast "Record Screen (toggle)") ───────────────
-- Added 2026-09-13 (Oops 20260913-171439); see screen_record.lua.
screenRecord = require("screen_record")

-- ── OCR a region to the clipboard (Raycast "OCR Screenshot → Clipboard") ────
-- Added 2026-10-26 (Oops 20261026-174443); see ocr_screen.lua.
ocrScreen = require("ocr_screen")

-- ── Focus Mode: distracting workspaces take 15 s to reach ───────────────────
-- Added 2026-09-14; see focus_gate.lua.
focusGate = require("focus_gate")

-- ── AeroSpace monitor mode follows plug/unplug and lid open/close ────────────
-- Added 2026-09-14; see monitor_mode.lua.
monitorMode = require("monitor_mode")

-- ── Brightness 0 → both screens dark (built-in gamma + DELL DDC luminance 0) ─
-- Added 2026-09-14; see brightness_blackout.lua.
brightnessBlackout = require("brightness_blackout")

-- ── alt-Q closes the window under the pointer (was AeroSpace `close`) ────────
-- Added 2026-09-14 (Oops 20260914-145958); see hover_close.lua.
hoverClose = require("hover_close")

-- ── name apps macOS left suspended (they make AeroSpace drop/restore windows) ─
-- Added 2026-09-15 (Oops 20260915-104240); see paused_apps.lua.
pausedApps = require("paused_apps")

-- ── secondary display stays stacked above the built-in ──────────────────────
-- Added 2026-09-20 (Oops 20260920-120528); see display_arrangement.lua.
displayArrangement = require("display_arrangement")

-- ── leader-timer done: sticky alert + sound even when the output is muted ────
-- Added 2026-09-22 (Oops 20260922-105249); see timer_alert.lua.
timerAlert = require("timer_alert")

-- ── Cmd+H / Cmd+L do nothing when there is nowhere to move ───────────────────
-- Added 2026-10-06 (Oops 20261006-200102); see hl_guard.lua.
hlGuard = require("hl_guard")

-- ── clipboard history for the lifelog (scripts/lifelog/clipboard.py ingests it) ──
-- Added 2026-10-07; see clipboard_log.lua.
clipboardLog = require("clipboard_log")

-- ── built-for-you: log presses of the chords Claude built, while under watch ──
-- Added 2026-10-19; see bfy_watch.lua.
bfyWatch = require("bfy_watch")

-- ── a non-user wake with the lid shut (⌥⎋ then lid close on the DELL) re-sleeps ─
-- Added 2026-10-29 (Oops 20261029-195452); see lid_resleep.lua.
lidResleep = require("lid_resleep")
