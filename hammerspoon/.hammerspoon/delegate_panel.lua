-- delegate_panel.lua: the Delegate window as a floating panel (Spotlight-style), not a browser tab.
--
-- Added 2026-11-04 (Matt: "I want this to be some floating UI that pops up instead of a web page").
-- It hosts the existing UI (scripts/delegate/ui.html, served by launchd delegate-serve at
-- http://127.0.0.1:47470) in an hs.webview: borderless, rounded, always on top, on every Space,
-- centred on the screen the mouse is on. Esc or a click elsewhere hides it; filing a task hides it;
-- links open in the default browser. The page talks back through the "delegate" message handler.
--
-- Opened by scripts/delegate/open-delegate.sh (the Option+Ctrl+J AeroSpace binding and the Raycast
-- command) with `hs -c 'delegatePanel.show()'`; show() captures the context itself first (M.capture). From Lua:
--   delegatePanel.show() / hide() / toggle() / reload()
-- Doc: ~/Obsidian/Main/areas/second-brain/delegate.md

local M = {}

M.url = "http://127.0.0.1:47470/?panel=1"
M.width, M.height = 760, 560
M.wv = nil
M.prev = nil          -- the window that was focused before the panel showed
M.shownAt = 0


local function frameFor()
  local scr = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local f = scr:frame()
  local w = math.min(M.width, f.w - 40)
  local h = math.min(M.height, f.h - 80)
  return { x = f.x + (f.w - w) / 2, y = f.y + math.max(36, (f.h - h) * 0.2), w = w, h = h }
end

local function openExternal(url)
  if url and url ~= "" then hs.urlevent.openURL(url) end
end

local function build()
  local uc = hs.webview.usercontent.new("delegate")
  uc:setCallback(function(msg)
    local b = msg and msg.body
    if b == "hide" or (type(b) == "table" and b.action == "hide") then
      M.hide(true)
    elseif type(b) == "table" and b.action == "open" then
      openExternal(b.url)
    elseif type(b) == "table" and b.action == "filed" then
      -- the page files the task, toasts, then asks to hide; nothing else to do here
      M.hide(true)
    end
  end)

  local wv = hs.webview.new(frameFor(), { developerExtrasEnabled = false }, uc)
  wv:windowStyle({ "borderless", "nonactivating" })
  wv:level(hs.drawing.windowLevels.floating)
  wv:behaviorAsLabels({ "canJoinAllSpaces", "fullScreenAuxiliary", "transient" })
  wv:allowTextEntry(true)
  wv:allowGestures(false)
  wv:allowNewWindows(false)
  wv:shadow(true)
  wv:transparent(true)
  wv:closeOnEscape(false)
  wv:deleteOnClose(false)

  -- links leave the panel for the default browser; only the local UI loads inside it.
  -- (request.URL arrives as an NSURL table, not a string: read its url field.)
  local function urlOf(tbl)
    local r = tbl and tbl.request
    local u = r and r.URL
    if type(u) == "table" then u = u.url or u.absoluteString or u.URL end
    return type(u) == "string" and u or ""
  end
  wv:policyCallback(function(action, _, tbl)
    local u = urlOf(tbl)
    if action == "newWindow" then
      openExternal(u)
      return false
    end
    if action == "navigationAction" then
      if u:find("^http://127%.0%.0%.1") or u:find("^about:") or u == "" then return true end
      openExternal(u)
      return false
    end
    return true
  end)

  -- click-away hides it (Spotlight behaviour); ignore the focus churn of the first half second
  wv:windowCallback(function(action, _, state)
    if action == "focusChange" and state == false and M.isShown()
       and (hs.timer.secondsSinceEpoch() - M.shownAt) > 0.5 then
      M.hide(false)
    elseif action == "closing" then
      M.wv = nil
      M.hsw = nil
    end
  end)

  -- once the page is in, hand it focus and the fresh context (the show() timer covers later shows)
  wv:navigationCallback(function(action, w, _, err)
    if action == "didFinishNavigation" then
      M.lastError = nil
      w:evaluateJavaScript("window.delegateActivated && window.delegateActivated()")
    elseif action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
      M.lastError = tostring(err and err.localizedDescription)
    end
  end)

  wv:url(M.url)
  return wv
end

function M.isShown()
  return M.wv ~= nil and M.wv:isVisible()
end

M.stamp = os.getenv("HOME") .. "/.local/state/delegate/panel.shown"
M.ctxPath = os.getenv("HOME") .. "/.local/state/delegate/context.json"

-- 2026-11-24 (MAT-5540, "make the delegate UI come up almost instantaneously"): the context used to be
-- captured by `python3 delegate context` (osascript x2, hs -c, pbpaste) BEFORE the panel was asked to show,
-- 0.75-1.6 s per press. Now Hammerspoon reads it natively (a few ms) right before show(), writes the same
-- context.json the server reads, and only the browser URL (AppleScript, slow) is filled in after the panel
-- is already up. Same fields and format as engine.capture_context().
local BROWSER_URL = {
  ["Google Chrome"] = 'tell application "Google Chrome" to get URL of active tab of front window',
  ["Dia"] = 'tell application "Dia" to get URL of active tab of front window',
  ["Arc"] = 'tell application "Arc" to get URL of active tab of front window',
  ["Brave Browser"] = 'tell application "Brave Browser" to get URL of active tab of front window',
  ["Microsoft Edge"] = 'tell application "Microsoft Edge" to get URL of active tab of front window',
  ["Chromium"] = 'tell application "Chromium" to get URL of active tab of front window',
  ["Safari"] = 'tell application "Safari" to get URL of front document',
}

local function nowIso() return os.date("!%Y-%m-%dT%H:%M:%S+00:00") end

local function writeCtx(ctx)
  local f = io.open(M.ctxPath, "w")
  if f then f:write(hs.json.encode(ctx)); f:close() end
end

local function trim(s) return type(s) == "string" and (s:gsub("^%s+", ""):gsub("%s+$", "")) or "" end

function M.capture()
  local ctx = { ts = nowIso(), host = "mac" }
  local app = hs.application.frontmostApplication()
  if app and app:name() == "Hammerspoon" then return nil end  -- the panel itself is in front: keep the last context
  if app then
    ctx.app = app:name() or ""
    ctx.bundle = app:bundleID() or ""
    local ok, title = pcall(function()
      local ax = hs.axuielement.applicationElement(app)
      ax:setTimeout(0.25)
      local w = ax:attributeValue("AXFocusedWindow")
      if w then w:setTimeout(0.25); return w:attributeValue("AXTitle") end
    end)
    ctx.title = ok and trim(title) or ""
  end
  -- the selection, through AX with a short timeout so a hung app can't stall the hotkey
  local ok, sel = pcall(function()
    local sw = hs.axuielement.systemWideElement()
    sw:setTimeout(0.25)
    local e = sw:attributeValue("AXFocusedUIElement")
    if e then e:setTimeout(0.25); return e:attributeValue("AXSelectedText") end
  end)
  sel = ok and trim(sel) or ""
  if sel ~= "" and #sel < 20000 then ctx.selection = sel end
  local clip = trim(hs.pasteboard.getContents())
  if clip ~= "" and #clip < 20000 and clip ~= sel then ctx.clipboard = clip end
  writeCtx(ctx)
  -- the page URL after the panel is up; then tell the page to re-read the context
  local script = BROWSER_URL[ctx.app or ""]
  if script then
    hs.task.new("/usr/bin/osascript", function(code, out)
      local url = trim(out)
      if code == 0 and url ~= "" then
        ctx.url = url
        ctx.ts = nowIso()
        writeCtx(ctx)
        if M.wv then M.wv:evaluateJavaScript("window.delegateActivated && window.delegateActivated()") end
      end
    end, { "-e", script }):start()
  end
  return ctx
end

local function touchStamp()
  local f = io.open(M.stamp, "w")
  if f then f:write(tostring(os.time())); f:close() end
end

function M.show(opts)
  if not (opts and opts.noCapture) then pcall(M.capture) end
  if not M.wv then M.wv = build() end
  if M.lastError then M.lastError = nil; M.wv:url(M.url) end  -- the server was down when the page last loaded
  touchStamp()
  local front = hs.window.frontmostWindow()
  if front and front:application() and front:application():name() ~= "Hammerspoon" then M.prev = front end
  M.wv:frame(frameFor())
  M.shownAt = hs.timer.secondsSinceEpoch()
  M.wv:show()
  M.wv:bringToFront(true)
  -- focus on the next run-loop turn so show() (and the hotkey's `hs -c`) returns as soon as the panel is up
  hs.timer.doAfter(0, function() M.focus(8) end)
  -- fresh context chips and the cursor in the box on every show, whether or not the AX window is seen yet
  M.wv:evaluateJavaScript("window.delegateActivated && window.delegateActivated()")
  return true
end

-- Make the panel the key window so typing lands in it. hswindow() (the AX view of our own window) can
-- be nil for a few ms after show(), so retry briefly; then tell the page it is on screen again
-- (refresh the context chips, focus the text box).
-- hswindow() walks Hammerspoon's AX windows (80-350 ms); the panel's NSWindow never changes
-- (deleteOnClose false), so look it up once and reuse it.
function M.focus(tries)
  if not M.wv then return end
  local w = M.hsw
  if not (w and pcall(function() return w:id() end) and w:id()) then
    w = M.wv:hswindow()
    M.hsw = w
  end
  if w then
    w:focus()
    M.wv:evaluateJavaScript("window.delegateActivated && window.delegateActivated()")
  elseif tries > 0 then
    hs.timer.doAfter(0.08, function() M.focus(tries - 1) end)
  end
end

function M.hide(byUser)
  if not M.wv then return true end
  M.wv:hide()
  if byUser and M.prev and M.prev:isStandard() then pcall(function() M.prev:focus() end) end
  return true
end

function M.toggle()
  if M.isShown() then return M.hide(true) end
  return M.show()
end

function M.reload()
  if M.wv then M.wv:reload() end
  return true
end

-- hammerspoon://delegate?action=show|hide|toggle|reload (default show)
hs.urlevent.bind("delegate", function(_, params)
  local a = params and params.action or "show"
  if a == "hide" then M.hide(true)
  elseif a == "toggle" then M.toggle()
  elseif a == "reload" then M.reload()
  elseif a == "shownocapture" then M.show({ noCapture = true })
  else M.show() end
end)

-- build the (hidden) webview now, so even the first press after a Hammerspoon reload shows a loaded page
hs.timer.doAfter(1, function() if not M.wv then M.wv = build() end end)

return M
