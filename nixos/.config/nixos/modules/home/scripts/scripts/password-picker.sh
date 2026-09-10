#!/usr/bin/env bash
# password-picker — pick a secret from the `pass` store via fuzzel, then either
# type it (wtype) or copy it (wl-copy, auto-clears). Nothing is ever stored in
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
    | fuzzel --dmenu --prompt 'pass> '
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
  printf '%s' "$pw" | wl-copy
  notify-send -i dialog-password "Password picker" "Copied '$entry' (clears in 45s)"
  (
    sleep 45
    wl-copy --clear
  ) >/dev/null 2>&1 &
  ;;
*)
  wtype -- "$pw"
  ;;
esac
