-- dayflow_follow.lua — opening Dayflow takes you to its window.
--
-- Dayflow runs all day with one main window, which AeroSpace keeps on its own
-- workspace `dayflow` (aerospace.nix on-window-detected rule). That rule only
-- fires for NEW windows. Opening the running app from Raycast/Dock/Cmd-Tab only
-- re-activates it, and AeroSpace did not follow: the window stayed in the
-- hidden corner (1727,1085) and Matt kept looking at Dia on ws 1 (Oops
-- 20261105-161827: "i cant open up dayflow").
--
-- Rule: when Dayflow is activated and none of its AeroSpace windows is on the
-- focused workspace, focus its first window; AeroSpace then switches to that
-- window's workspace (its home, `dayflow`). Nothing is moved. If a Dayflow
-- window is already on the focused workspace, nothing happens.
-- Log: Hammerspoon console, lines prefixed "dayflow_follow:".

local M = {}

local AEROSPACE = "/opt/homebrew/bin/aerospace"
local BUNDLE = "teleportlabs.com.Dayflow"

local function run(args, cb)
  hs.task.new(AEROSPACE, function(code, out) if cb then cb(code, out or "") end end, args):start()
end

-- `apply` false = report the plan only.
function M.follow(apply, done)
  done = done or function() end
  run({ "list-workspaces", "--focused" }, function(wcode, wout)
    local cur = wcode == 0 and (wout:gsub("%s+$", "")) or ""
    run({ "list-windows", "--monitor", "all", "--app-bundle-id", BUNDLE,
          "--format", "%{window-id}|%{workspace}" }, function(code, out)
      if code ~= 0 or cur == "" then return done("skip: aerospace query failed") end
      local first
      for id, ws in out:gmatch("(%d+)|([^\n]+)") do
        if ws == cur then return done("noop: Dayflow already on " .. cur) end
        first = first or { id = id, ws = ws }
      end
      if not first then return done("skip: no Dayflow windows") end
      local plan = "focus --window-id " .. first.id .. " (ws " .. first.ws .. ", from " .. cur .. ")"
      if not apply then return done(plan) end
      run({ "focus", "--window-id", first.id }, function(fcode)
        done(plan .. " exit=" .. fcode)
      end)
    end)
  end)
end

M.watcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.activated and app and app:bundleID() == BUNDLE then
    M.follow(true, function(r) print("dayflow_follow: " .. r) end)
  end
end)
M.watcher:start()

return M
