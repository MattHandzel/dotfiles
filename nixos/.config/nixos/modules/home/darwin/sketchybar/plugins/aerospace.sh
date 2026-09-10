#!/usr/bin/env bash
# AeroSpace workspaces → one `space.<name>` item each.
#
# Shown: every workspace that has a window, plus the focused one (even if it
# is empty). Focused is a Mauve pill with crust text — the single loud colour
# on the bar. The others are quiet: name in subtext, app glyphs beside it in
# sketchybar-app-font so you can see what lives where without switching.
#
# Called on: aerospace_workspace_change (from ~/.aerospace.toml), on
# front_app_switched (a window moved), on a 30 s timer, and once at startup.
# Items are rebuilt only when the set of workspaces changed, otherwise just
# recoloured.

set +u  # empty arrays under bash 3.2 would trip -u
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"

AEROSPACE=/opt/homebrew/bin/aerospace
SB=/opt/homebrew/bin/sketchybar
FONT="JetBrainsMono Nerd Font"

focused="${FOCUSED_WORKSPACE:-$($AEROSPACE list-workspaces --focused 2>/dev/null)}"
[ -z "$focused" ] && exit 0

# Numbered workspaces first (numerically), then named ones (alphabetically).
order_stable() {
  local all; all="$(sort -u)"
  printf '%s\n' "$all" | grep -E '^[0-9]+$' | sort -n
  printf '%s\n' "$all" | grep -vE '^[0-9]+$' | sort
}

# Desired set: every occupied workspace plus the focused one.
# (macOS ships bash 3.2 — no mapfile — so arrays are filled with read loops.)
wanted=("$focused")
while IFS= read -r w; do [ -n "$w" ] && wanted+=("$w"); done \
  < <($AEROSPACE list-workspaces --monitor all --empty no 2>/dev/null)
tmp=(); while IFS= read -r w; do [ -n "$w" ] && tmp+=("$w"); done \
  < <(printf '%s\n' "${wanted[@]}" | order_stable)
wanted=("${tmp[@]}")

# Existing items.
existing=(); while IFS= read -r w; do [ -n "$w" ] && existing+=("$w"); done \
  < <($SB --query bar 2>/dev/null | /opt/homebrew/bin/jq -r '.items[]' | grep '^space\.' | sed 's/^space\.//')

# Rebuild when the set differs.
if [ "$(printf '%s\n' "${wanted[@]}")" != "$(printf '%s\n' "${existing[@]}" | order_stable)" ]; then
  args=()
  for w in "${existing[@]}"; do args+=(--remove "space.$w"); done
  for w in "${wanted[@]}"; do
    args+=(--add item "space.$w" left
           --set "space.$w"
             icon="$w"
             icon.font="$FONT:Bold:12.5"
             icon.padding_left=8
             icon.padding_right=3
             label.font="sketchybar-app-font:Regular:14.0"
             label.padding_left=0
             label.padding_right=8
             label.y_offset=-1
             background.drawing=on
             background.height=22
             background.corner_radius=5
             padding_left=1
             padding_right=1
             click_script="$AEROSPACE workspace $w"
           --move "space.$w" before front_app)
  done
  [ ${#args[@]} -gt 0 ] && $SB "${args[@]}"
fi

# Recolour + refresh the app glyphs.
args=()
for w in "${wanted[@]}"; do
  glyphs=""
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    __icon_map "$app"
    glyphs+="${icon_result:-:default:}"
  done < <($AEROSPACE list-windows --workspace "$w" --format '%{app-name}' 2>/dev/null | sort -u)
  if [ "$w" = "$focused" ]; then
    args+=(--set "space.$w"
             label="$glyphs"
             label.drawing=$([ -n "$glyphs" ] && echo on || echo off)
             icon.color="$CRUST" label.color="$CRUST"
             background.color="$MAUVE")
  else
    args+=(--set "space.$w"
             label="$glyphs"
             label.drawing=$([ -n "$glyphs" ] && echo on || echo off)
             icon.color="$SUBTEXT0" label.color="$SUBTEXT0"
             background.color="$SURFACE0")
  fi
done
[ ${#args[@]} -gt 0 ] && $SB "${args[@]}"
exit 0
