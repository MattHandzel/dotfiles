#!/usr/bin/env bash
# Paste the SECOND-most-recent cliphist entry, leaving clipboard history order intact.
#
# Order preservation relies on cliphist deduping by content: we briefly put entry
# #2 on the clipboard (cliphist moves it to the top), paste it, then restore entry
# #1 (cliphist moves that back to the top). Net history order is unchanged, and the
# clipboard ends up holding what it held before.
set -uo pipefail

notify() { notify-send -u normal -i edit-paste "Paste 2nd clip" "$1"; }

# macOS: Raycast owns the clipboard history and has no CLI to read entry #2, so
# open its Clipboard History (the second row is the one you want; ↵ pastes it).
if [[ "$(uname)" == Darwin ]]; then
  open "raycast://extensions/raycast/clipboard-history/clipboard-history"
  exit 0
fi

second_line=$(cliphist list | sed -n 2p)
if [[ -z $second_line ]]; then
  notify "No second item in clipboard history."
  exit 0
fi

cur=$(mktemp) || exit 1
new=$(mktemp) || exit 1
trap 'rm -f "$cur" "$new"' EXIT

# Preserve the current clipboard's MIME type so restoring an image/rich-text clip
# doesn't silently downgrade it to text/plain.
cur_type=$(wl-paste --list-types 2>/dev/null | head -n1)
[[ -z $cur_type ]] && cur_type="text/plain"
wl-paste --no-newline --type "$cur_type" >"$cur" 2>/dev/null

if ! printf '%s' "$second_line" | cliphist decode >"$new" 2>/dev/null || [[ ! -s $new ]]; then
  notify "Could not decode the second clipboard entry."
  exit 1
fi

restore() {
  if [[ -s $cur ]]; then
    wl-copy --type "$cur_type" <"$cur"
  else
    wl-copy --clear
  fi
}

wl-copy <"$new"
sleep 0.12

# wtype drives its own virtual keyboard and sends its own modifier state, so the
# Ctrl+Alt still physically held by the keybind does not contaminate this Ctrl+V.
if ! wtype -M ctrl -k v -m ctrl; then
  restore
  notify "wtype failed; clipboard restored, nothing pasted."
  exit 1
fi

sleep 0.12
restore
