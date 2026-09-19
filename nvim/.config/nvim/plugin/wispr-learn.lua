-- Teach Wispr Flow the corrections you make here.
-- Commands: :WisprLearn (scan this buffer now), :WisprLearnWord {phrase} [heard...]
--
-- Wispr Flow only learns from edits it can watch through Accessibility in the
-- few seconds after it pastes; in kitty/Neovim that never works, so "UVM" ->
-- "Neovim" fixed by hand stays unlearned. On every :w of a prose buffer this
-- hands the buffer to `wispr-learn scan` (modules/home/darwin/wispr-learn.py),
-- which aligns the recent dictations against the text and adds each corrected
-- word to Wispr's dictionary the way its own learner would. Nothing runs when
-- Wispr Flow's database is absent, and each (dictation, phrase) is learned once.

local PROSE = {
  markdown = true, text = true, org = true, rst = true,
  tex = true, plaintex = true, asciidoc = true, norg = true, vimwiki = true,
  gitcommit = true, mail = true,
}

local DEBOUNCE_MS = 1500
-- WISPR_LEARN_DB (also honoured by the CLI) points a test at a scratch copy.
local DB = vim.env.WISPR_LEARN_DB or vim.fn.expand("~/Library/Application Support/Wispr Flow/flow.sqlite")

local timers = {}
local warned = false

-- The activated symlink, then PATH, then the repo file (works between editing
-- the flake and activating it).
local function cli()
  local bin = vim.fn.expand("~/.local/bin/wispr-learn")
  if vim.fn.executable(bin) == 1 then
    return { bin }
  end
  if vim.fn.executable("wispr-learn") == 1 then
    return { "wispr-learn" }
  end
  local repo = vim.fn.expand("~/dotfiles/nixos/.config/nixos/modules/home/darwin/wispr-learn.py")
  if vim.fn.filereadable(repo) == 1 and vim.fn.executable("python3") == 1 then
    return { "python3", repo }
  end
  return nil
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "wispr-learn" })
end

local function run(args, stdin, on_done)
  local base = cli()
  if not base then
    if not warned then
      warned = true
      notify("wispr-learn is not installed (modules/home/darwin/wispr-learn.nix)", vim.log.levels.WARN)
    end
    return
  end
  local cmd = vim.list_extend(vim.deepcopy(base), args)
  vim.system(cmd, { stdin = stdin, text = true }, function(res)
    vim.schedule(function()
      vim.g.wispr_learn_last = { code = res.code, stdout = res.stdout, stderr = res.stderr }
      on_done(res)
    end)
  end)
end

local function scan(buf, verbose)
  if vim.fn.filereadable(DB) ~= 1 then
    if verbose then notify("no Wispr Flow database at " .. DB, vim.log.levels.WARN) end
    return
  end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if #text < 20 then return end
  run({ "scan", "--json" }, text, function(res)
    if res.code ~= 0 then
      if verbose or not warned then
        warned = true
        notify("scan failed: " .. vim.trim(res.stderr or ""), vim.log.levels.WARN)
      end
      return
    end
    local ok, learned = pcall(vim.json.decode, res.stdout or "")
    if ok and type(learned) == "table" and #learned > 0 then
      local parts = {}
      for _, e in ipairs(learned) do
        parts[#parts + 1] = string.format("%s (heard \u{201C}%s\u{201D})", e.phrase, e.observedSource)
      end
      notify("Wispr Flow learned: " .. table.concat(parts, ", "))
    elseif verbose then
      notify("nothing new to learn from this buffer")
    end
  end)
end

local group = vim.api.nvim_create_augroup("WisprLearn", { clear = true })

vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= "" or not PROSE[vim.bo[ev.buf].filetype] then return end
    if timers[ev.buf] then timers[ev.buf]:stop() end
    timers[ev.buf] = vim.defer_fn(function()
      timers[ev.buf] = nil
      scan(ev.buf, false)
    end, DEBOUNCE_MS)
  end,
})

vim.api.nvim_create_user_command("WisprLearn", function()
  scan(vim.api.nvim_get_current_buf(), true)
end, { desc = "Teach Wispr Flow the corrections in this buffer" })

vim.api.nvim_create_user_command("WisprLearnWord", function(opts)
  local phrase = opts.fargs[1]
  local heard = #opts.fargs > 1 and table.concat(vim.list_slice(opts.fargs, 2), " ") or nil
  local args = { "add", phrase }
  if heard then vim.list_extend(args, { "--heard", heard }) end
  run(args, nil, function(res)
    if res.code ~= 0 then
      notify("add failed: " .. vim.trim(res.stderr or ""), vim.log.levels.WARN)
    else
      notify(vim.trim(res.stdout or ""))
    end
  end)
end, {
  nargs = "+",
  desc = "Add a phrase to Wispr Flow's dictionary: :WisprLearnWord Neovim UVM",
})
