-- ── built-for-you: log presses of the chords under watch ─────────────────────
-- Added 2026-10-19 (built-for-you slice 2). When Claude builds Matt a chord
-- (an AeroSpace binding, a Hammerspoon hotkey, a tmux prefix key), the use
-- check (~/Obsidian/Main/scripts/built-for-you/usecheck.py) puts it on
-- ~/.local/state/built-for-you/watch-chords.json until he has used it:
--   [{"id": "chord:alt-y", "mods": ["alt"], "key": "y"}, ...]
-- A keyDown matching one of those exactly (same key, same set of cmd/alt/ctrl/
-- shift) appends one line to ~/.local/state/built-for-you/use-<date>.jsonl,
-- the same shape as registry.log_use(): {"ts", "id", "src", "what"}. Nothing
-- else is recorded, and with an empty list the tap is not even running.
--
-- Why not the Oops key trail (oops.lua): its recordKey() counts ⌥+letter as
-- typing (Polish ą, ę, ś), and leader and keypad keys likewise, so the trail
-- deliberately keeps no record of exactly the chords this module needs. That
-- is the right call for a trail that may hold typed text; leave it alone.
--
-- The tap never swallows the event (the callback returns false), so the chord
-- still reaches AeroSpace, the hotkey, or the app. Every callback is pcall'd.
local M = {}

M.DIR = os.getenv("HOME") .. "/.local/state/built-for-you"
M.WATCH = M.DIR .. "/watch-chords.json"
M.byKey = {}   -- key name -> list of {id, mods = {alt = true, ...}}
M.last = {}    -- id -> second of the last line (one per second at most)

local MODS = { "cmd", "alt", "ctrl", "shift" }

local function stamp(now)
  local z = os.date("%z", now) -- "-0500" -> "-05:00"
  return os.date("%Y-%m-%dT%H:%M:%S", now) .. z:sub(1, 3) .. ":" .. z:sub(4)
end

function M.logUse(id, what)
  local now = os.time()
  if M.last[id] == now then return end
  M.last[id] = now
  hs.fs.mkdir(M.DIR)
  local f = io.open(M.DIR .. "/use-" .. os.date("%Y-%m-%d", now) .. ".jsonl", "a")
  if f then
    f:write(hs.json.encode({ ts = stamp(now), id = id, src = "chord", what = what }), "\n")
    f:close()
  end
end

function M.load()
  M.byKey = {}
  local f = io.open(M.WATCH, "r")
  local list = {}
  if f then
    local ok, v = pcall(hs.json.decode, f:read("*a"))
    f:close()
    if ok and type(v) == "table" then list = v end
  end
  local n = 0
  for _, w in ipairs(list) do
    if w.id and w.key then
      local mods = {}
      for _, m in ipairs(w.mods or {}) do mods[string.lower(m)] = true end
      local k = string.lower(w.key)
      M.byKey[k] = M.byKey[k] or {}
      table.insert(M.byKey[k], { id = w.id, mods = mods, what = table.concat(w.mods or {}, "+") .. "+" .. k })
      n = n + 1
    end
  end
  if n > 0 then M.tap:start() else M.tap:stop() end
  return n
end

M.tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(e)
  pcall(function()
    local key = hs.keycodes.map[e:getKeyCode()]
    local cands = key and M.byKey[string.lower(key)]
    if not cands then return end
    local f = e:getFlags()
    for _, c in ipairs(cands) do
      local same = true
      for _, m in ipairs(MODS) do
        if (f[m] or false) ~= (c.mods[m] or false) then same = false break end
      end
      if same then M.logUse(c.id, c.what) end
    end
  end)
  return false
end)

-- the use check rewrites the list each night; pick it up without a reload
M.watcher = hs.pathwatcher.new(M.DIR, function(paths)
  for _, p in ipairs(paths) do
    if p:sub(-#"watch-chords.json") == "watch-chords.json" then pcall(M.load) return end
  end
end)
hs.fs.mkdir(M.DIR)
M.watcher:start()
pcall(M.load)

return M
