-- jobs_panel.lua: the panel behind the red "N down" pill in the menu bar (sketchybar item jobs_down).
--
-- Added 2026-11-10. Matt, about the pill's old click (a 15-second text alert): "There's no UI that I can use,
-- and there's no way that I can interact with it." Clicking the pill now opens this floating panel under the
-- bar: each job that is down, what it does, what is wrong in a sentence, how long, what Claude is doing about
-- it, and buttons (the answers to Claude's question when it waits on him, Fix it, Run it again, Not now,
-- Details with the log tail, Open full log, Ignore for good), plus Check again, the jobs failing for under
-- 30 minutes, and the muted or ignored ones. It also shows the collector's alerts (M.alert): clicking one
-- opens this panel on that job.
--
-- Same shape as delegate_panel.lua (borderless hs.webview, on every Space, Esc / click-away hides it) but no
-- server: the page is scripts/bugs/jobs-panel.html, filled in by `error-collector panel --html`. The page asks
-- for things through the "jobs" message handler; this file passes only the known action names and a job name
-- to `error-collector panel-act`, as argv (no shell). The collector checks the job is on its current list and
-- takes the label, bug id and log path from its own data, so nothing in a message can run anything else.
--
-- Opened by sketchybar's plugins/jobs_down.sh click with `open -g hammerspoon://jobs-panel?action=toggle`.
-- From Lua: jobsPanel.show() / hide() / toggle(). Doc: ~/Obsidian/Main/areas/second-brain/error-collector.md

local M = {}

M.ec = "/etc/profiles/per-user/matth/bin/error-collector"
M.width = 600
M.wv = nil
M.prev = nil
M.shownAt = 0
M.hiddenAt = 0
M.checking = false
M.lastError = nil

local ACTIONS = { run = true, open = true, fix = true, permit = true, answer = true, snooze = true,
                  ignore = true, unignore = true }
M.board = "http://127.0.0.1:47740/"  -- the bug board web UI (bug-board-ui), for the "wait for your yes" alert

-- top right of the screen the mouse is on, just under the bar, so it drops down from the pill
local function frameFor(h)
  local scr = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local f = scr:fullFrame()
  local w = math.min(M.width, f.w - 24)
  local maxH = f.h - 60
  h = math.max(120, math.min(h or 420, maxH))
  local mx = hs.mouse.absolutePosition().x
  local x = math.max(f.x + 12, math.min(mx - w + 60, f.x + f.w - w - 12))
  return { x = x, y = f.y + 40, w = w, h = h }
end

local function js(code)
  if M.wv then M.wv:evaluateJavaScript(code) end
end

-- run error-collector with argv; cb(ok, stdout) on the main thread. Never through a shell.
local function ec(args, cb)
  local t = hs.task.new(M.ec, function(code, out, err)
    cb(code == 0 and out and out:match("^%s*[%[{<]") ~= nil, out or "", err or "")
  end, args)
  if not t or not t:start() then cb(false, "", "could not start error-collector") end
end

function M.refresh()
  if not M.wv or M.checking then return end
  M.checking = true
  js("window.ecChecking && ecChecking(true)")
  ec({ "panel" }, function(ok, out, err)
    M.checking = false
    if ok then
      js("ecData(" .. out .. ")")
    else
      js("ecError(" .. hs.json.encode({ "The check failed: " .. ((err ~= "" and err) or out):sub(1, 300) }):sub(2, -2) .. ")")
    end
  end)
end

local function act(a, job, option)
  if not ACTIONS[a] or type(job) ~= "string" or not job:match("^[%w%._%-]+$") or #job > 120 then return end
  local args = { "panel-act", a, job }
  if a == "answer" then
    local n = math.tointeger(tonumber(option))
    if not n or n < 0 or n > 9 then return end
    table.insert(args, "--option"); table.insert(args, tostring(n))
  end
  ec(args, function(ok, out, err)
    if ok then
      js("ecResult(" .. out .. ")")
    else
      js("ecResult(" .. hs.json.encode({ job = job, ok = false, msg = "error-collector failed: " .. (err ~= "" and err or out):sub(1, 300) }) .. ")")
    end
    if a ~= "open" then M.refresh() end  -- show where things stand now (a passing job leaves the list)
  end)
end

local function build(html)
  local uc = hs.webview.usercontent.new("jobs")
  uc:setCallback(function(msg)
    local b = msg and msg.body
    if type(b) ~= "table" then return end
    if b.action == "hide" then M.hide(true)
    elseif b.action == "refresh" then M.refresh()
    elseif b.action == "act" then act(b.act, b.job, b.option)
    elseif b.action == "size" and tonumber(b.h) and M.wv then
      local fr = M.wv:frame()
      local want = frameFor(tonumber(b.h))
      if math.abs(fr.h - want.h) > 2 then M.wv:frame({ x = fr.x, y = fr.y, w = fr.w, h = want.h }) end
    end
  end)

  local wv = hs.webview.new(frameFor(420), { developerExtrasEnabled = false }, uc)
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

  -- nothing navigates away from the page (request.URL is an NSURL table, not a string)
  wv:policyCallback(function(action, _, tbl)
    if action == "newWindow" then return false end
    if action == "navigationAction" then
      local u = tbl and tbl.request and tbl.request.URL
      if type(u) == "table" then u = u.url or u.absoluteString end
      return u == nil or u == "" or tostring(u):find("^about:") ~= nil
    end
    return true
  end)

  -- click-away hides it, like the Delegate panel; ignore the focus churn of the first half second
  wv:windowCallback(function(action, _, state)
    if action == "focusChange" and state == false and M.isShown()
       and (hs.timer.secondsSinceEpoch() - M.shownAt) > 0.5 then
      M.hide(false)
    elseif action == "closing" then
      M.wv = nil
    end
  end)

  wv:navigationCallback(function(action, _, _, err)
    if action == "didFailNavigation" or action == "didFailProvisionalNavigation" then
      M.lastError = tostring(err and err.localizedDescription)
    end
  end)

  wv:html(html)
  return wv
end

function M.isShown()
  return M.wv ~= nil and M.wv:isVisible()
end

local function present(job)
  local front = hs.window.frontmostWindow()
  if front and front:application() and front:application():name() ~= "Hammerspoon" then M.prev = front end
  local fr = M.wv:frame()
  local want = frameFor(fr.h)
  M.wv:frame(want)
  M.shownAt = hs.timer.secondsSinceEpoch()
  M.wv:show()
  M.wv:bringToFront(true)
  M.focus(8)
  js("window.ecShown && ecShown()")
  if type(job) == "string" and job:match("^[%w%._%-]+$") then js("ecFocusJob(" .. hs.json.encode({ job }):sub(2, -2) .. ")") end
  M.refresh()  -- the page shows the last scan's list at once and says "checking…" until this one is in
end

function M.show(job)
  if M.wv then present(job); return true end
  -- first open: the page with the last scan's list (instant), then a fresh check
  ec({ "panel", "--html", "--cached" }, function(ok, out, err)
    if not ok then
      M.lastError = (err ~= "" and err) or out
      hs.alert.show("Jobs panel: error-collector failed (" .. M.lastError:sub(1, 120) .. ")", 6)
      return
    end
    M.wv = build(out)
    hs.timer.doAfter(0.15, function() present(job) end)
  end)
  return true
end

-- Make the panel the key window so Escape and Tab reach it. hswindow() can be nil for a few ms after show().
function M.focus(tries)
  if not M.wv then return end
  local w = M.wv:hswindow()
  if w then
    w:focus()
  elseif tries > 0 then
    hs.timer.doAfter(0.08, function() M.focus(tries - 1) end)
  end
end

function M.hide(byUser)
  if not M.wv then return true end
  if M.wv:isVisible() then M.hiddenAt = hs.timer.secondsSinceEpoch() end
  M.wv:hide()
  if byUser and M.prev and M.prev:isStandard() then pcall(function() M.prev:focus() end) end
  return true
end

-- A click on the pill while the panel is up first takes focus away (which hides it), then arrives here:
-- a toggle within half a second of that hide means "close it", not "open it again".
function M.toggle()
  if M.isShown() then return M.hide(true) end
  if hs.timer.secondsSinceEpoch() - M.hiddenAt < 0.5 then return true end
  return M.show()
end

-- ── alerts that lead somewhere ──────────────────────────────────────────────
-- error-collector's notify() comes here (Matt, 2026-11-10: notifications he was "unable to do anything about").
-- A macOS notification that opens the panel (or the bug board) when clicked, and for a job that is down
-- ("loud") also a card on screen for 30 s that does the same; the card isn't held by Do Not Disturb.
-- The target is one of two fixed places, never a URL from the caller.
local function openTarget(target, job)
  if target == "board" then hs.urlevent.openURL(M.board) else M.show(job) end
end

M.cards = {}
local function card(title, body, target, job)
  for _, c in ipairs(M.cards) do c:delete() end
  M.cards = {}
  local scr = hs.screen.mainScreen():fullFrame()
  local w, h = 380, 96
  local c = hs.canvas.new({ x = scr.x + scr.w - w - 12, y = scr.y + 40, w = w, h = h })
  c:level(hs.canvas.windowLevels.overlay)
  c:behaviorAsLabels({ "canJoinAllSpaces", "transient" })
  c:clickActivating(false)
  c:appendElements(
    { type = "rectangle", action = "fill", roundedRectRadii = { xRadius = 10, yRadius = 10 },
      fillColor = { hex = "#1e1e2e" }, strokeColor = { hex = "#f38ba8" }, strokeWidth = 1.5,
      trackMouseUp = true },
    { type = "text", text = title, textSize = 14, textColor = { hex = "#f38ba8" },
      textFont = ".AppleSystemUIFontBold", frame = { x = 14, y = 10, w = w - 28, h = 20 } },
    { type = "text", text = body, textSize = 12, textColor = { hex = "#cdd6f4" },
      frame = { x = 14, y = 32, w = w - 28, h = 40 } },
    { type = "text", text = "Click to open  ·  it closes by itself", textSize = 11, textColor = { hex = "#a6adc8" },
      frame = { x = 14, y = 72, w = w - 28, h = 16 } })
  c:mouseCallback(function()
    c:delete(); M.cards = {}
    openTarget(target, job)
  end)
  c:show()
  M.cards = { c }
  -- kept in M so it isn't garbage-collected (an unreferenced hs.timer can be, and the card would stay up)
  if M.cardTimer then M.cardTimer:stop() end
  M.cardTimer = hs.timer.doAfter(30, function() if M.cards[1] == c then c:delete(); M.cards = {} end end)
end

function M.alert(title, body, loud, target, job)
  target = (target == "board") and "board" or "panel"
  job = (type(job) == "string" and job:match("^[%w%._%-]+$")) and job or nil
  M.notes = M.notes or {}
  table.insert(M.notes, 1, hs.notify.new(function() openTarget(target, job) end,
    { title = title, informativeText = body, soundName = "Funk", withdrawAfter = 0 }):send())
  M.notes[21] = nil  -- keep the last 20 so their click callbacks stay alive
  if loud then card(title, body, target, job) end
end

-- hammerspoon://jobs-panel?action=show|hide|toggle[&job=…] (default toggle)
--                         ?action=alert&title=…&body=…&loud=1&target=panel|board&job=…
hs.urlevent.bind("jobs-panel", function(_, params)
  params = params or {}
  local a = params.action or "toggle"
  if a == "hide" then M.hide(true)
  elseif a == "show" then M.show(params.job)
  elseif a == "alert" then M.alert(params.title or "Background jobs", params.body or "", params.loud == "1", params.target, params.job)
  else M.toggle() end
end)

return M
