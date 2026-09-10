#!/usr/bin/env bash
# kb-lang-status.sh — waybar custom/kb-lang widget driver.
#
# Usage:
#   kb-lang-status            → emit JSON for current layout (default)
#   kb-lang-status status     → same as above
#   kb-lang-status toggle     → cycle to next layout on the main keyboard, then
#                               signal waybar (RTMIN+8) to refresh instantly
#
# We read `hyprctl devices -j` and trust only the keyboard with main=true,
# because Hyprland exposes 8+ pseudo-keyboards (power-button, video-bus,
# intel-hid-events, …) that report the FIRST kb_layout regardless of the
# user's actual `alt+caps` toggle state.

set -euo pipefail

main_field() {
  # $1 = jq field path
  hyprctl devices -j 2>/dev/null \
    | jq -r ".keyboards[] | select(.main == true) | $1 // empty" \
    | head -1
}

case "${1:-status}" in
  toggle)
    name=$(main_field '.name')
    if [[ -n "$name" ]]; then
      hyprctl switchxkblayout "$name" next >/dev/null 2>&1 || true
      # Refresh waybar immediately rather than waiting for the next poll.
      pkill -RTMIN+8 waybar 2>/dev/null || true
    fi
    ;;
  status|*)
    layout=$(main_field '.active_keymap')
    case "$layout" in
      Polish*)                     text="🇵🇱"; cls="pl" ;;
      "English (US)"*|English*)    text="🇺🇸"; cls="en" ;;
      German*)                     text="🇩🇪"; cls="de" ;;
      French*)                     text="🇫🇷"; cls="fr" ;;
      Spanish*)                    text="🇪🇸"; cls="es" ;;
      "")                          text="?";   cls="unknown"; layout="(no main keyboard)" ;;
      *)                           text="$layout"; cls="other" ;;
    esac
    # JSON-escape layout for the tooltip; it can contain quotes/backslashes.
    tooltip=$(jq -Rn --arg s "$layout" '$s')   # produces "\"Polish\""
    printf '{"text":"%s","class":"%s","tooltip":"Layout: %s — click to switch"}\n' \
      "$text" "$cls" "${tooltip//\"/}"
    ;;
esac
