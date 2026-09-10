#!/usr/bin/env bash
# Battery: Nerd Font glyph by level, green on power, yellow ≤ 30, red ≤ 15.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"

batt="$(/usr/bin/pmset -g batt)"
pct="$(printf '%s' "$batt" | /usr/bin/grep -Eo '[0-9]+%' | head -1 | tr -d %)"
[ -z "$pct" ] && { /opt/homebrew/bin/sketchybar --set "$NAME" drawing=off; exit 0; }

charging=""
printf '%s' "$batt" | /usr/bin/grep -q 'AC Power' && charging=1

case "$pct" in
  9[0-9]|100) icon="󰁹" ;;
  8[0-9])     icon="󰂁" ;;
  7[0-9])     icon="󰂀" ;;
  6[0-9])     icon="󰁿" ;;
  5[0-9])     icon="󰁾" ;;
  4[0-9])     icon="󰁽" ;;
  3[0-9])     icon="󰁼" ;;
  2[0-9])     icon="󰁻" ;;
  1[0-9])     icon="󰁺" ;;
  *)          icon="󰂎" ;;
esac

color="$GREEN"
if [ -n "$charging" ]; then
  icon="󰂄"; color="$GREEN"
elif [ "$pct" -le 15 ]; then
  color="$RED"
elif [ "$pct" -le 30 ]; then
  color="$YELLOW"
fi

/opt/homebrew/bin/sketchybar --set "$NAME" drawing=on icon="$icon" icon.color="$color" label="${pct}%"
