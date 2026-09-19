#!/usr/bin/env bash
# keybinds — searchable list of every AeroSpace binding (Hyprland SUPER+F1).
# The Linux original (scripts/keybinds.sh) grepped hyprland.conf into fuzzel;
# this reads ~/.aerospace.toml and uses `choose`, the picker the other Mac
# scripts already rely on. Picking a row copies it to the clipboard.
# Ported by hand to ~/.local/bin on 2026-09-10; brought into the flake 2026-09-12.
set -uo pipefail
CFG="${AEROSPACE_CONFIG:-$HOME/.aerospace.toml}"
[[ -r "$CFG" ]] || { echo "keybinds: cannot read $CFG" >&2; exit 1; }

awk '
  /^\[mode\.[a-z-]+\.binding\]/ {
    mode=$0; gsub(/^\[mode\./,"",mode); gsub(/\.binding\]$/,"",mode)
    inmode=1; printf "\n──  %s mode  ──\n", mode; next
  }
  inmode && /^[a-z0-9]+(-[a-z0-9]+)* *= *[\x27\[]/ {
    key=$0; sub(/ *=.*/,"",key)
    cmd=$0; sub(/^[^=]*= */,"",cmd); gsub(/^\x27|\x27$/,"",cmd)
    printf "%-22s %s\n", key, cmd
  }
' "$CFG" | choose -n 30 -w 110 | {
  read -r picked || exit 0
  [[ -n "$picked" ]] && printf '%s' "$picked" | pbcopy
}
