#!/usr/bin/env bash
# Focus (or launch) the lifelog UI and open its Search view.
# Bound to SUPER+SHIFT+L in hyprland (see hyprland/config.nix).
set -euo pipefail

BIN="$HOME/Projects/lifelog/target/release/lifelog-server-frontend"

find_addr() {
  hyprctl clients -j | jq -r '.[] | select(.class=="lifelog-server-frontend") | .address' | head -1
}

addr=$(find_addr)

if [[ -z "$addr" ]]; then
  if [[ ! -x "$BIN" ]]; then
    notify-send "lifelog" "UI binary missing: $BIN" 2>/dev/null || true
    exit 1
  fi
  # WebKit runtime libs come from the repo's frontend devshell; resolve once
  # and cache (nix store paths stay valid until GC).
  LD_CACHE="$HOME/.cache/lifelog-frontend-ldpath"
  if [[ ! -s "$LD_CACHE" ]]; then
    (cd "$HOME/Projects/lifelog" && nix develop .#frontend --command sh -c 'printf "%s" "$LD_LIBRARY_PATH"' > "$LD_CACHE")
  fi
  LD_LIBRARY_PATH="$(cat "$LD_CACHE")" "$BIN" >/dev/null 2>&1 &
  disown
  for _ in $(seq 1 50); do
    addr=$(find_addr)
    [[ -n "$addr" ]] && break
    sleep 0.2
  done
fi

[[ -z "$addr" ]] && exit 1
hyprctl dispatch focuswindow "address:$addr"
sleep 0.15
# In-app shortcut: Ctrl+Shift+S switches to the Search view.
hyprctl dispatch sendshortcut "CTRL SHIFT,S,address:$addr"
