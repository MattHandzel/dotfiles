-- OCR a screen region to the clipboard. Added 2026-10-26 (Oops 20261026-174443:
-- Raycast "OCR Screenshot → Clipboard" never captured anything).
--
-- Lives in Hammerspoon for the same reason as screen_record.lua: Raycast's
-- Screen Recording (TCC) grant is denied, so `screencapture -i` spawned by its
-- script command fails with "could not create image from rect". Hammerspoon
-- holds the grant, and children of hs.task are attributed to it. Reached via
--   open -g hammerspoon://ocr-screenshot     (Raycast "OCR Screenshot → Clipboard")
-- Runs the nix `ocr-screenshot` (screencapture -i → tesseract → pbcopy).
local M = {}

local BIN = "/etc/profiles/per-user/" .. os.getenv("USER") .. "/bin/ocr-screenshot"

M.task = nil

function M.run()
  if M.task and M.task:isRunning() then return end
  M.task = hs.task.new(BIN, function(code, out, err)
    M.task = nil
    local text = (out or ""):match("Extracted Text:\n\n(.*)$")
    if code == 0 and text and text:match("%S") then
      local first = text:match("[^\n]+") or ""
      hs.alert.show("OCR copied: " .. first:sub(1, 60), 1.5)
    elseif code == 0 then
      hs.alert.show("OCR found no text", 1.5)
    elseif not (out or ""):match("canceled") or (err or ""):match("%S") then
      hs.alert.show("OCR failed: " .. ((err or ""):match("[^\n]+") or (out or ""):match("[^\n]+$") or ("exit " .. code)), 3)
    end
  end)
  if not M.task:start() then
    M.task = nil
    hs.alert.show("OCR failed: could not start " .. BIN, 3)
  end
end

hs.urlevent.bind("ocr-screenshot", function() M.run() end)

return M
