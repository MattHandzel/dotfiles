#!/usr/bin/env bash
# clip2md — replace the clipboard's rich text with its Markdown equivalent.
#
# Saul's clipboard2markdown trick: copy formatted text (Notion, Google Docs, a
# web page), run this, then paste clean Markdown anywhere (Discord, a commit
# message, Obsidian). Bound to SUPER+SHIFT+M; also available inline via the
# espanso ";;md" trigger. Leaves the clipboard untouched when there is no HTML
# flavour to convert (i.e. you copied plain text), so it is safe to fire blind.
set -euo pipefail

html=$(wl-paste --type text/html 2>/dev/null || true)

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

printf '%s' "$md" | wl-copy
notify-send -t 2500 -i edit-paste "clip2md → Markdown" "Clipboard converted to Markdown. Paste anywhere."
