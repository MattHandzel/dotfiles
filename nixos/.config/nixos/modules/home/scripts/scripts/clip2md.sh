#!/usr/bin/env bash
# clip2md — replace the clipboard's rich text with its Markdown equivalent.
#
# Saul's clipboard2markdown trick: copy formatted text (Notion, Google Docs, a
# web page), run this, then paste clean Markdown anywhere (Discord, a commit
# message, Obsidian). Bound to SUPER+SHIFT+M; also available inline via the
# espanso ";;md" trigger. Leaves the clipboard untouched when there is no HTML
# flavour to convert (i.e. you copied plain text), so it is safe to fire blind.
set -euo pipefail

if [[ "$(uname)" == Darwin ]]; then
  # macOS keeps rich text as the «class HTML» flavour; osascript prints it as
  # «data HTML<hex>», so strip the wrapper and un-hex it.
  html=$(osascript -e 'try' -e 'the clipboard as «class HTML»' -e 'end try' 2>/dev/null \
    | sed -E 's/^«data HTML//; s/»$//' | xxd -r -p || true)
  clip_copy() { pbcopy; }
else
  html=$(wl-paste --type text/html 2>/dev/null || true)
  clip_copy() { wl-copy; }
fi

if [ -z "$html" ]; then
  notify-send -t 2500 -i edit-paste "clip2md" "No rich text on the clipboard — nothing to convert."
  exit 0
fi

# gfm = GitHub-flavoured Markdown (what the original webapp produces); -raw_html
# drops the stray tags pandoc would otherwise pass through; --wrap=none keeps
# paragraphs on one line so pasted Markdown reflows in the destination.
md=$(printf '%s' "$html" | pandoc --from html --to gfm-raw_html --wrap=none 2>/dev/null || true)

if [ -z "$md" ]; then
  notify-send -t 2500 -u critical -i dialog-error "clip2md" "pandoc produced no output."
  exit 1
fi

printf '%s' "$md" | clip_copy
notify-send -t 2500 -i edit-paste "clip2md → Markdown" "Clipboard converted to Markdown. Paste anywhere."

# `clip2md --paste`: also paste it where the cursor is (what the espanso ;;md
# trigger did inline; on macOS the Raycast script command uses this).
if [[ "${1:-}" == --paste ]]; then
  if [[ "$(uname)" == Darwin ]]; then
    osascript -e 'tell application "System Events" to keystroke "v" using command down'
  else
    wtype -M ctrl -k v -m ctrl
  fi
fi
