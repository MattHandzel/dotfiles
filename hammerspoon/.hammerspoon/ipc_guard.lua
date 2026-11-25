-- ipc_guard.lua: stop `hs -c` clients from crashing Hammerspoon (added 2026-11-15).
--
-- Hammerspoon 1.1.1's hs.ipc sends a CLI its output/result with CFMessagePortSendRequest, which
-- waits for the CLI's answer in a nested run loop. The "Hammerspoon" port is serviced in that loop,
-- so a CLI that gives up (timeout, kill) and sends UNREGISTER, or the 60 s prune timer, runs
-- remote:delete() while the send is still using that port. delete() frees the CFMessagePort and
-- the send traps on it: EXC_BREAKPOINT in __CFCheckCFInfoPACSignature <- CFMessagePortIsValid <-
-- CFMessagePortSendRequest <- ipc_sendMessage (crash 2026-11-12 14:46 UTC, bug listener item
-- err-Hammerspoon-20261112-155035; system-problem-log 2026-11-15 09:05).
--
-- The fix wraps the hs.ipc object methods: a delete() that lands during a send on the same port is
-- deferred until that send returns, and further sends to a port waiting to be deleted are refused.
-- Load it right after require("hs.ipc"). Repro: ~/Obsidian/Main/scripts/bugs/repros/
-- err-Hammerspoon-20261112-155035.sh. Drop this file once upstream hs.ipc retains the port during
-- a send.
local M = { installed = false }

-- wrap(send, delete) -> guardedSend, guardedDelete. Separate from install() so the repro can test
-- the ordering with stand-in functions instead of real ports.
function M.wrap(send, delete)
  local busy = setmetatable({}, { __mode = "k" }) -- port userdata -> sends in flight
  local pending = setmetatable({}, { __mode = "k" }) -- port userdata -> delete deferred

  local function guardedDelete(self)
    if busy[self] then
      pending[self] = true
      M.deferred = (M.deferred or 0) + 1 -- times a mid-send delete was caught (each one a crash before)
      return
    end
    pending[self] = nil
    return delete(self)
  end

  local function guardedSend(self, ...)
    if pending[self] then return false, "message port was deleted" end
    busy[self] = (busy[self] or 0) + 1
    local r = table.pack(pcall(send, self, ...))
    busy[self] = busy[self] - 1
    if busy[self] == 0 then
      busy[self] = nil
      if pending[self] then
        pending[self] = nil
        delete(self)
      end
    end
    if not r[1] then error(r[2], 2) end
    return table.unpack(r, 2, r.n)
  end

  return guardedSend, guardedDelete
end

function M.install()
  local mt = hs.getObjectMetatable("hs.ipc")
  if not mt then return false end
  if mt.__ipcGuard then
    M.installed = true
    return true
  end
  mt.sendMessage, mt.delete = M.wrap(mt.sendMessage, mt.delete)
  mt.__ipcGuard = true
  M.installed = true
  return true
end

return M
