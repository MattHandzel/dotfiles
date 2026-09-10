#!/usr/bin/env bash
# Output volume. $INFO is the new level on volume_change; otherwise ask.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"

settings="$(/usr/bin/osascript -e 'get volume settings' 2>/dev/null)"
vol="${INFO:-$(printf '%s' "$settings" | /usr/bin/sed -E 's/.*output volume:([0-9]+).*/\1/')}"
muted=""
printf '%s' "$settings" | /usr/bin/grep -q 'output muted:true' && muted=1

if [ -n "$muted" ] || [ "${vol:-0}" -eq 0 ]; then
  icon="󰝟"; color="$OVERLAY1"; label="—"
else
  color="$LAVENDER"; label="${vol}%"
  if   [ "$vol" -ge 66 ]; then icon="󰕾"
  elif [ "$vol" -ge 33 ]; then icon="󰖀"
  else                         icon="󰕿"
  fi
fi

/opt/homebrew/bin/sketchybar --set "$NAME" icon="$icon" icon.color="$color" label="$label"
