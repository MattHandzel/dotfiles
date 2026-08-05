-- :ReloadConfig — re-apply the config in THIS session, no restart.
--
-- Why this exists: lazy.nvim's change_detection prints "Config Change Detected.
-- Reloading..." and then calls Plugin.load(), which only re-parses the plugin
-- SPEC. It does not re-run options/mappings/autocommands, and it does not re-run
-- `config`/`opts` for plugins that are already loaded. So the toast says the
-- config reloaded while nothing you actually edited took effect — which is why
-- restarting nvim seemed to be the only fix, at the cost of every terminal and
-- Claude session living in that instance.
--
-- What this reloads: your own lua modules (options, mappings, autocommands, and
-- anything under configs/ or plugins/). Every autocmd in autocommands.lua is in
-- a `clear = true` augroup so re-running is idempotent rather than additive.
--
-- What this does NOT reload, honestly: an already-loaded plugin's setup(). Lua
-- cannot un-run a plugin's side effects. For that use `:Lazy reload <plugin>`,
-- which the notification below reminds you of.

local M = {}

-- Modules owned by this config. Anything matching these is dropped from
-- package.loaded so the next require re-reads the file from disk.
-- nvconfig/chadrc are here because NvChad's statusline re-reads
-- require("nvconfig").ui.statusline on every redraw — so dropping the cached
-- copy is enough for a chadrc edit (theme, statusline order/modules) to apply
-- in-session. Without it, chadrc was the one file where :ReloadConfig silently
-- did nothing and only a restart worked.
local OWNED =
  { "^options$", "^mappings$", "^autocommands$", "^configs%.", "^plugins%.", "^nvconfig$", "^chadrc$" }

-- Never unload the reloader itself mid-reload, and leave lazy's own internals
-- alone -- yanking those from package.loaded corrupts its plugin state.
local PROTECTED = { ["configs.reload"] = true }

local function owned(name)
  if PROTECTED[name] then
    return false
  end
  for _, pat in ipairs(OWNED) do
    if name:match(pat) then
      return true
    end
  end
  return false
end

--- Re-apply the user config. Returns count of modules reloaded, and any error.
function M.reload()
  local cleared = {}
  for name, _ in pairs(package.loaded) do
    if owned(name) then
      package.loaded[name] = nil
      table.insert(cleared, name)
    end
  end

  -- Order matters: options first (mappings/autocmds may read them).
  local failed = {}
  for _, mod in ipairs({ "options", "autocommands", "mappings" }) do
    local ok, err = pcall(require, mod)
    if not ok then
      table.insert(failed, mod .. ": " .. tostring(err))
    end
  end

  return cleared, failed
end

-- Root of the editable config. Files are edited at their real dotfiles path
-- (nvim.lua + lua/) -- ~/.config/nvim/init.lua is a read-only Nix symlink.
local CONFIG_ROOT = vim.fn.expand("~/dotfiles/nvim/.config/nvim")

--- Auto-reload on write, so saving a config file just applies it.
local function setup_autoreload()
  local group = vim.api.nvim_create_augroup("UserConfigAutoReload", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = CONFIG_ROOT .. "/*.lua",
    callback = function(args)
      -- Editing the reloader itself is the one case auto-reload cannot handle
      -- safely: it is PROTECTED from unloading, so a save would silently run
      -- the OLD code and look like the edit did nothing.
      if args.file and args.file:match("configs/reload%.lua$") then
        vim.notify("configs/reload.lua changed — restart nvim to pick it up", vim.log.levels.WARN)
        return
      end
      local _, failed = M.reload()
      if #failed > 0 then
        vim.notify("Auto-reload FAILED:\n" .. table.concat(failed, "\n"), vim.log.levels.ERROR)
      else
        -- Deliberately terse and low level: this fires on every config save,
        -- and a loud toast each time is how people learn to ignore toasts.
        vim.notify("config reloaded", vim.log.levels.INFO)
      end
    end,
    desc = "Re-apply nvim config on save",
  })
end

function M.setup()
  setup_autoreload()

  vim.api.nvim_create_user_command("ReloadConfig", function()
    local cleared, failed = M.reload()
    if #failed > 0 then
      vim.notify(
        "Config reload FAILED:\n" .. table.concat(failed, "\n"),
        vim.log.levels.ERROR
      )
      return
    end
    vim.notify(
      ("Reloaded %d module(s). Plugin setup() is NOT re-run — use :Lazy reload <plugin> for that.")
        :format(#cleared),
      vim.log.levels.INFO
    )
  end, { desc = "Re-apply nvim config without restarting" })
end

return M
