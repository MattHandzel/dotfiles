-- brain-search.lua — semantic search over the Obsidian second brain, from Neovim.
--
-- <leader>fB  normal mode: prompt for a query (seeded with the word under the cursor)
-- <leader>fB  visual mode: search for the selected text, no typing
--
-- Talks to the same service the shell client uses (scripts/brain-search.sh):
-- POST http://matts-server:47772/search. The server runs on CUDA; a reranked
-- query takes ~1.9-2.2s, which is why this prompts and then searches rather than
-- searching on every keystroke — a live picker at that latency feels broken.
--
-- Reranking is ON. It costs ~1.5s over the embedding-only path and is worth it:
-- for "how do I get better at forecasting" the un-reranked top hit is an unrelated
-- meeting transcript, while the reranked list leads with the weekly-review and
-- epistemics notes. The first rerank after a service restart pays a cold model
-- load and can exceed the timeout, so a timeout falls back to embedding-only
-- rather than failing the search.
--
-- Every interaction is appended to areas/second-brain/search-log.jsonl: the query,
-- every result with its rank and score, and which one was actually opened. That
-- log is the training signal for making retrieval better over time — a query
-- where Matt opens result #7 is a ranking failure we can only see if it is recorded.

local M = {}

local API = "http://matts-server:47772/search"
local VAULT = vim.fn.expand("~/Obsidian/Main")
local LOG = VAULT .. "/areas/second-brain/search-log.jsonl"
local TOP_K = 40 -- over-fetch, because we discard duplicates below
local SHOW_K = 20
local TIMEOUT_MS = 20000

-- The index contains every agent worktree under .claude/worktrees — 56k markdown
-- files against 13.6k real vault notes, i.e. ~80% of the corpus is duplicate
-- checkouts of notes that already exist at their real path. Unfiltered, 7 of the
-- top 10 hits for a typical query are worktree copies of each other. Dropping
-- them client-side is a stopgap; the real fix is excluding them at index time.
local JUNK_PREFIXES = { "%.claude/", "%.stversions/", "%.git/", "%.trash/" }

local function is_junk(rel)
  for _, p in ipairs(JUNK_PREFIXES) do
    if rel:match("^" .. p) then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------- logging

local function log_event(event)
  event.at = os.date("!%Y-%m-%dT%H:%M:%SZ")
  event.surface = "nvim"
  local ok, line = pcall(vim.json.encode, event)
  if not ok then
    return
  end
  vim.schedule(function()
    local fh = io.open(LOG, "a")
    if not fh then
      return
    end
    fh:write(line .. "\n")
    fh:close()
  end)
end

----------------------------------------------------------------------- search

--- Query the service. cb(err, results, elapsed_ms). Kept free of UI so it can be
--- exercised headlessly.
function M.query(q, cb, opts)
  opts = opts or {}
  local rerank = opts.rerank ~= false
  local payload = vim.json.encode({
    query = q,
    top_k = TOP_K,
    rerank = rerank,
    full_text = false,
    group_by_note = true,
  })
  local started = vim.uv.hrtime()
  vim.system({
    "curl", "-s", "-X", "POST", API,
    "-H", "Content-Type: application/json",
    "-d", payload,
    "--max-time", tostring(math.floor(TIMEOUT_MS / 1000)),
  }, { text = true }, function(res)
    local elapsed = math.floor((vim.uv.hrtime() - started) / 1e6)
    if res.code ~= 0 then
      return cb(("search service unreachable (curl exit %d)"):format(res.code), nil, elapsed)
    end
    if not res.stdout or res.stdout == "" then
      return cb("search service returned nothing (timeout?)", nil, elapsed)
    end
    local ok, decoded = pcall(vim.json.decode, res.stdout)
    if not ok or type(decoded) ~= "table" then
      return cb("could not parse response: " .. tostring(res.stdout):sub(1, 200), nil, elapsed)
    end
    if decoded.detail then -- FastAPI error shape
      return cb("service error: " .. vim.inspect(decoded.detail):sub(1, 200), nil, elapsed)
    end
    cb(nil, decoded, elapsed)
  end)
end

--- Locate the retrieved chunk inside the file so we land on the passage, not line 1.
local function chunk_line(path, text)
  if not text or text == "" then
    return 1
  end
  local needle = text:gsub("^%s+", ""):match("^[^\n]+") or ""
  needle = needle:sub(1, 60)
  if #needle < 12 then
    return 1
  end
  local fh = io.open(path, "r")
  if not fh then
    return 1
  end
  local n = 0
  for line in fh:lines() do
    n = n + 1
    if line:find(needle, 1, true) then
      fh:close()
      return n
    end
  end
  fh:close()
  return 1
end

------------------------------------------------------------------------- UI

local function to_items(results)
  local items = {}
  local seen = {}
  for _, r in ipairs(results) do
    local rel = r.rel_path or r.path or "?"
    -- Skip worktree/versioned duplicates, and collapse repeats of the same note.
    if is_junk(rel) or seen[rel] then
      goto continue
    end
    seen[rel] = true
    local snippet = (r.text or ""):gsub("%s+", " "):sub(1, 220)
    items[#items + 1] = {
      idx = #items + 1,
      rank = #items + 1,
      score = r.score or 0,
      file = r.path or (VAULT .. "/" .. rel),
      rel_path = rel,
      chunk = r.text or "",
      text = rel .. " " .. snippet, -- what the picker's own fuzzy filter matches on
      snippet = snippet,
    }
    if #items >= SHOW_K then
      break
    end
    ::continue::
  end
  return items
end

local function open_item(item, query, results, elapsed, meta)
  local line = chunk_line(item.file, item.chunk)
  vim.cmd.edit(vim.fn.fnameescape(item.file))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
  vim.cmd("normal! zz")
  log_event({
    event = "open",
    query = query,
    elapsed_ms = elapsed,
    reranked = (meta or {}).reranked,
    chosen = { rel_path = item.rel_path, rank = item.rank, score = item.score, line = line },
    results = vim.tbl_map(function(r)
      return { rel_path = r.rel_path, rank = r.rank, score = r.score }
    end, results),
  })
end

local function present(query, results, elapsed, meta)
  meta = meta or {}
  if #results == 0 then
    vim.notify(("brain-search: no results for %q (%dms)"):format(query, elapsed), vim.log.levels.WARN)
    log_event({ event = "empty", query = query, elapsed_ms = elapsed, reranked = meta.reranked, results = {} })
    return
  end

  local items = to_items(results)
  local opened = false

  local ok_snacks, Snacks = pcall(require, "snacks")
  if ok_snacks and Snacks.picker then
    Snacks.picker({
      title = ("Brain Search: %s (%dms)"):format(query, elapsed),
      items = items,
      format = function(item)
        return {
          { ("%.2f "):format(item.score), "SnacksPickerLabel" },
          { item.rel_path, "SnacksPickerFile" },
          { "  " .. item.snippet, "SnacksPickerComment" },
        }
      end,
      preview = "file",
      confirm = function(picker, item)
        picker:close()
        if item then
          opened = true
          open_item(item, query, items, elapsed, meta)
        end
      end,
      on_close = function()
        if not opened then
          log_event({
            event = "abandoned",
            query = query,
            elapsed_ms = elapsed,
            reranked = meta.reranked,
            results = vim.tbl_map(function(r)
              return { rel_path = r.rel_path, rank = r.rank, score = r.score }
            end, items),
          })
        end
      end,
    })
    return
  end

  -- Fallback when snacks.picker is unavailable, so the mapping never dead-ends.
  vim.ui.select(items, {
    prompt = ("Brain Search: %s"):format(query),
    format_item = function(item)
      return ("%.2f  %s  %s"):format(item.score, item.rel_path, item.snippet:sub(1, 80))
    end,
  }, function(choice)
    if choice then
      open_item(choice, query, items, elapsed, meta)
    else
      log_event({ event = "abandoned", query = query, elapsed_ms = elapsed, reranked = meta.reranked, results = {} })
    end
  end)
end

--- Run a search and show the picker.
function M.search(query)
  if not query or query:gsub("%s", "") == "" then
    return
  end
  vim.notify(("brain-search: %s…"):format(query), vim.log.levels.INFO)
  M.query(query, function(err, results, elapsed)
    if err then
      -- Most likely a cold reranker model load after a service restart. Retry
      -- once without reranking so a search never simply fails.
      return M.query(query, function(err2, results2, elapsed2)
        vim.schedule(function()
          if err2 then
            vim.notify("brain-search: " .. err2, vim.log.levels.ERROR)
            log_event({ event = "error", query = query, elapsed_ms = elapsed2, error = err2 })
            return
          end
          vim.notify("brain-search: reranker slow, showing embedding-only results", vim.log.levels.WARN)
          present(query, results2, elapsed2, { reranked = false })
        end)
      end, { rerank = false })
    end
    vim.schedule(function()
      present(query, results, elapsed, { reranked = true })
    end)
  end)
end

local function visual_selection()
  local save = vim.fn.getreg("v")
  vim.cmd([[noautocmd normal! "vy]])
  local text = vim.fn.getreg("v")
  vim.fn.setreg("v", save)
  return (text or ""):gsub("[\r\n]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.setup()
  vim.api.nvim_create_user_command("BrainSearch", function(o)
    if o.args ~= "" then
      M.search(o.args)
    else
      vim.ui.input({ prompt = "Brain search: " }, function(q)
        M.search(q)
      end)
    end
  end, { nargs = "*", desc = "Semantic search of the second brain" })

  vim.keymap.set("n", "<leader>fB", function()
    vim.ui.input({ prompt = "Brain search: ", default = vim.fn.expand("<cword>") }, function(q)
      M.search(q)
    end)
  end, { desc = "Brain search (second brain)" })

  vim.keymap.set("v", "<leader>fB", function()
    M.search(visual_selection())
  end, { desc = "Brain search selection" })
end

return M
