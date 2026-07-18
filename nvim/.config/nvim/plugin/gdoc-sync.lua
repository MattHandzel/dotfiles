-- Google Docs <-> Markdown sync with CriticMarkup comments
-- Commands: :GDocPull, :GDocPush, :GDocLink <url>

local gdoc_sync = vim.fn.expand("~/Obsidian/Main/scripts/gdoc-sync/gdoc-sync.sh")

-- CriticMarkup syntax highlighting for comments
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.cmd([[
      syntax match CriticMarkupComment /\V{>>\.\{-}<<}/ containedin=ALL
      highlight CriticMarkupComment guifg=#7a7a7a gui=italic ctermfg=242 cterm=italic
    ]])
  end,
})

-- :GDocPull - pull from linked Google Doc
vim.api.nvim_create_user_command("GDocPull", function()
  local file = vim.fn.expand("%:p")
  if file == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  vim.notify("Pulling from Google Docs...", vim.log.levels.INFO)
  local cmd = string.format("%s pull %s 2>&1", vim.fn.shellescape(gdoc_sync), vim.fn.shellescape(file))

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then vim.notify(line, vim.log.levels.INFO) end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          vim.cmd("edit!")
          vim.notify("Pull complete.", vim.log.levels.INFO)
        else
          vim.notify("Pull failed (exit " .. code .. ")", vim.log.levels.ERROR)
        end
      end)
    end,
  })
end, { desc = "Pull from linked Google Doc" })

-- :GDocPush - push to linked Google Doc
vim.api.nvim_create_user_command("GDocPush", function()
  local file = vim.fn.expand("%:p")
  if file == "" then
    vim.notify("No file open", vim.log.levels.ERROR)
    return
  end

  vim.cmd("write")
  vim.notify("Pushing to Google Docs...", vim.log.levels.INFO)
  local cmd = string.format("%s push %s 2>&1", vim.fn.shellescape(gdoc_sync), vim.fn.shellescape(file))

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then vim.notify(line, vim.log.levels.INFO) end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          vim.notify("Push complete.", vim.log.levels.INFO)
        else
          vim.notify("Push failed (exit " .. code .. ")", vim.log.levels.ERROR)
        end
      end)
    end,
  })
end, { desc = "Push to linked Google Doc" })

-- :GDocLink <url_or_id> - link current file to a Google Doc
vim.api.nvim_create_user_command("GDocLink", function(opts)
  local url = opts.args
  if url == "" then
    vim.notify("Usage: :GDocLink <google_doc_url_or_id>", vim.log.levels.ERROR)
    return
  end

  local file = vim.fn.expand("%:p")
  local cmd = string.format("%s link %s %s 2>&1", vim.fn.shellescape(gdoc_sync), vim.fn.shellescape(file), vim.fn.shellescape(url))

  local output = vim.fn.system(cmd)
  if vim.v.shell_error == 0 then
    vim.notify("Linked to Google Doc. Use :GDocPull to sync.", vim.log.levels.INFO)
  else
    vim.notify("Link failed: " .. output, vim.log.levels.ERROR)
  end
end, { nargs = 1, desc = "Link current file to a Google Doc" })
