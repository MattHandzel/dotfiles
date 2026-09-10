#!/usr/bin/env bash
# password-picker — pick a secret from the `pass` store via fuzzel (Linux) or
# `choose` (macOS), then either type it (wtype / osascript keystroke) or copy it
# (wl-copy / pbcopy, auto-clears). Nothing is ever stored in
# plaintext: entries live GPG-encrypted under ~/.password-store, unlocked by your
# GPG key (gpg-agent caches the passphrase for the session).
#
#   password-picker        → type the chosen password into the focused window
#   password-picker copy   → copy to clipboard for 45s instead of typing
#
# Setup (one-time, outside this repo so secrets never touch git):
#   pass init <your-gpg-key-id>
#   pass insert email/gmail        # paste the password when prompted
#   pass insert wifi/home
# Migrate the old espanso plaintext password the same way, then delete it there.

set -euo pipefail

# macOS: the picker is `choose`, typing is System Events, the clipboard is
# pbcopy. Same shape as the Linux path so the two never drift.
if [[ "$(uname)" == Darwin ]]; then
  pick() { choose -n 20 -p 'pass> '; }
  copy() { pbcopy; }
  clear_clip() { pbcopy </dev/null; }
  type_text() {
    # argv, not string interpolation, so passwords with quotes/backslashes are safe.
    osascript -e 'on run argv' -e 'tell application "System Events" to keystroke (item 1 of argv)' -e 'end run' -- "$1"
  }
else
  pick() { fuzzel --dmenu --prompt 'pass> '; }
  copy() { wl-copy; }
  clear_clip() { wl-copy --clear; }
  type_text() { wtype -- "$1"; }
fi

store="${PASSWORD_STORE_DIR:-$HOME/.password-store}"

if [ ! -d "$store" ]; then
  notify-send -u critical -i dialog-password "Password picker" \
    "No password store at $store.\nRun:  pass init <gpg-id>"
  exit 1
fi

# List entries: every *.gpg under the store, minus prefix and suffix.
entry="$(
  cd "$store" && fd -e gpg --type f . 2>/dev/null \
    | sed 's/\.gpg$//' | sort \
    | pick
)" || exit 0
[ -n "$entry" ] || exit 0

# Convention: the password is the first line of the entry.
pw="$(pass show "$entry" 2>/dev/null | head -n1 || true)"
if [ -z "$pw" ]; then
  notify-send -u critical -i dialog-password "Password picker" "Empty or undecryptable entry: $entry"
  exit 1
fi

case "${1:-type}" in
copy)
  printf '%s' "$pw" | copy
  notify-send -i dialog-password "Password picker" "Copied '$entry' (clears in 45s)"
  (
    sleep 45
    clear_clip
  ) >/dev/null 2>&1 &
  ;;
*)
  type_text "$pw"
  ;;
esac
