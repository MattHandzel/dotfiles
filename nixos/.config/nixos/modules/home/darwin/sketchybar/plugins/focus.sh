#!/usr/bin/env bash
# Focus Mode pill: shows whether Focus Mode is on, and toggles it when clicked.
#
#   on   peach pill "󱫠 Focus"   distracting apps take 15 s (focus_gate.lua)
#   off  dim glyph  "󱫪"
#
# It also makes Focus Mode follow the calendar LOCALLY (2026-09-14). The normal
# path, the focus-mode-sync agent, listens to the home server, and when the
# server is offline nothing turns focus on for a Deep work block. This script
# runs inside SketchyBar, which (unlike a launchd agent) holds Calendar access,
# so icalBuddy can see the current event. The rule matches the server resolver:
# a current event titled "deep work", or tagged DEEP_WORK / SHALLOW_WORK /
# ADMIN_WORK in its notes, means Focus ON. The calendar wins, so turning it off
# by hand during such a block is undone within a minute. When the block ends,
# focus goes OFF only if this script was the one that turned it on.
#
# Called with: "click" (click_script), on a 60 s timer, and on
# aerospace_workspace_change (toggle-focus-mode fires that, so the pill redraws
# at once).

source "${CONFIG_DIR:-$HOME/.config/sketchybar}/colors.sh"
SB=/opt/homebrew/bin/sketchybar
ICALBUDDY=/opt/homebrew/bin/icalBuddy
TOGGLE="/etc/profiles/per-user/$(id -un)/bin/toggle-focus-mode"
FLAG=/tmp/focus_mode
STATE_DIR="$HOME/.local/state/focus"
AUTO="$STATE_DIR/calendar-turned-on" # exists = this script turned focus on

draw() {
  if [ -e "$FLAG" ]; then
    $SB --set focus icon="󱫠" icon.color="$CRUST" label="Focus" label.drawing=on \
      label.color="$CRUST" background.drawing=on background.color="$PEACH"
  else
    $SB --set focus icon="󱫪" icon.color="$SUBTEXT0" label.drawing=off background.drawing=off
  fi
}

calendar_check() {
  [ -x "$ICALBUDDY" ] || return
  local now
  # Titles + notes of events happening right now. On error (no Calendar
  # access), icalBuddy prints "error: …" and we change nothing.
  now="$($ICALBUDDY -nc -nrd -npn -ea -b '' -iep 'title,notes' eventsNow 2>&1)" || return
  case "$now" in error:*) return ;; esac
  mkdir -p "$STATE_DIR"
  if printf '%s' "$now" | grep -qiE 'deep work|category: *(DEEP_WORK|SHALLOW_WORK|ADMIN_WORK)'; then
    if [ ! -e "$FLAG" ]; then
      "$TOGGLE" on >/dev/null 2>&1
      : >"$AUTO"
    fi
  elif [ -e "$AUTO" ]; then
    rm -f "$AUTO"
    [ -e "$FLAG" ] && "$TOGGLE" off >/dev/null 2>&1
  fi
}

case "${1:-$SENDER}" in
  click)
    rm -f "$AUTO" # a manual choice; the calendar re-asserts during a block
    "$TOGGLE" >/dev/null 2>&1
    ;;
  aerospace_workspace_change) : ;;
  *) calendar_check ;;
esac
draw
