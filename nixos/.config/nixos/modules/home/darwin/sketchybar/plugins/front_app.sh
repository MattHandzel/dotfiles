#!/usr/bin/env bash
# Front app glyph + "App — window title", truncated by label.max_chars.
# $INFO carries the app name on front_app_switched; otherwise ask AeroSpace.

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/plugins/icon_map.sh"
AEROSPACE=/opt/homebrew/bin/aerospace

app="${INFO:-}"
title=""
line="$(/opt/homebrew/bin/aerospace list-windows --focused --format '%{app-name}%{tab}%{window-title}' 2>/dev/null | head -1)"
if [ -n "$line" ]; then
  [ -z "$app" ] && app="${line%%$'\t'*}"
  title="${line#*$'\t'}"
fi
[ -z "$app" ] && app="$(/usr/bin/osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)"

if [ -z "$app" ]; then
  /opt/homebrew/bin/sketchybar --set "$NAME" drawing=off
  exit 0
fi

__icon_map "$app"

# Collapse whitespace; drop a title that merely repeats the app name.
title="$(printf '%s' "$title" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')"
if [ -z "$title" ] || [ "$title" = "$app" ]; then
  label="$app"
else
  label="$app — $title"
fi

/opt/homebrew/bin/sketchybar --set "$NAME" drawing=on icon="$icon_result" label="$label"
