-- bitwarden_follow.lua — Bitwarden comes to the workspace you are on.
--
-- Bitwarden.app runs all day (login agent, modules/home/darwin/bitwarden.nix)
-- with a single window, and AeroSpace had no home for it: that window sat on
-- whatever workspace it last landed on (17 on 2026-09-13). Opening Bitwarden
-- from Raycast/Dock/Cmd-Tab only re-activates the running app, so AeroSpace
-- either jumped to that workspace or left the window hidden off-screen and
-- showed the bare desktop (Oops 20260913-171335: "it moves me to a random
-- workspace").
--
-- Rule: when Bitwarden is activated, its windows are moved onto AeroSpace's
-- focused workspace (asked at that moment, not the lagging oops-ws URL hook)
-- and the first one is focused. If a Bitwarden window is already on the
-- focused workspace, nothing happens: Matt went there on purpose.
-- Oops 20260913-171806: an earlier "AeroSpace followed the activation < 1.5 s
-- ago -> use the previous workspace" branch read Matt's deliberate click on
-- workspace 17 as a follow and threw him (and Bitwarden) back to workspace
-- claude. A Raycast activation does not make AeroSpace switch (171335
-- keys.log: focus went to the Dock, no workspace change), so it is gone.

local M = {}

local AEROSPACE = "/opt/homebrew/bin/aerospace"
local BUNDLE = "com.bitwarden.desktop"

local function run(args, cb)
  hs.task.new(AEROSPACE, function(code, out) if cb then cb(code, out or "") end end, args):start()
end

-- Decide the target workspace and the moves; `apply` false = return the plan only.
function M.pull(apply, done)
  run({ "list-workspaces", "--focused" }, function(wcode, wout)
    local cur = wcode == 0 and (wout:gsub("%s+$", "")) or ""
    run({ "list-windows", "--monitor", "all", "--app-bundle-id", BUNDLE,
          "--format", "%{window-id}|%{workspace}" }, function(code, out)
      if code ~= 0 or cur == "" then
        if done then done("skip: no workspace/windows") end
        return
      end
      local wins = {}
      for id, ws in out:gmatch("(%d+)|([^\n]+)") do wins[#wins + 1] = { id = id, ws = ws } end
      if #wins == 0 then
        if done then done("skip: no Bitwarden windows") end
        return
      end
      for _, w in ipairs(wins) do
        if w.ws == cur then
          if done then done("noop: Bitwarden already on " .. cur) end
          return
        end
      end
      local plan = {}
      for _, w in ipairs(wins) do
        plan[#plan + 1] = { "move-node-to-workspace", "--window-id", w.id, cur }
      end
      plan[#plan + 1] = { "focus", "--window-id", wins[1].id }
      local lines = {}
      for _, p in ipairs(plan) do lines[#lines + 1] = table.concat(p, " ") end
      if not apply then
        if done then done(table.concat(lines, "\n")) end
        return
      end
      local i = 0
      local function step()
        i = i + 1
        if i > #plan then
          if done then done(table.concat(lines, "\n")) end
          return
        end
        run(plan[i], step)
      end
      step()
    end)
  end)
end

M.watcher = hs.application.watcher.new(function(_, event, app)
  if event == hs.application.watcher.activated and app and app:bundleID() == BUNDLE then
    M.pull(true, function(r) print("bitwarden_follow: " .. r:gsub("\n", " ; ")) end)
  end
end)
M.watcher:start()

return M
