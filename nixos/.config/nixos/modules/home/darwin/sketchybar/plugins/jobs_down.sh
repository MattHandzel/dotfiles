#!/usr/bin/env bash
# Jobs down: a red warning sign with the number of Matt's background jobs that
# are down (last run failed, crash-looping, stuck, or their expected output went
# stale, for 30+ min). Hidden when everything works. It stays up until the job
# works again, which is the point: a banner is missed, a board item is buried
# (2026-11-04..10: the meeting listener failed 4,800 passes and 18 meetings went
# unprocessed while its board item waited among ~190 others).
#
# Data: ~/.local/state/error-collector/down.json, written by
# `error-collector scan` every 5 min (scripts/bugs/error-collector in the vault),
# which fires `jobs_down_update`. Click = the jobs panel (see the click branch below).
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"
SB=/opt/homebrew/bin/sketchybar
F="$HOME/.local/state/error-collector/down.json"
EC=/etc/profiles/per-user/matth/bin/error-collector

# Click: toggle the jobs panel (~/.hammerspoon/jobs_panel.lua): each down job with its log, what Claude is doing
# about it, and Run it again / Fix with Claude / Open log / Ignore. If Hammerspoon isn't running, the old text
# alert can't show either, so fall back to a macOS notification with the list.
if [ "${1:-}" = "click" ]; then
  if /usr/bin/pgrep -xq Hammerspoon; then
    /usr/bin/open -g "hammerspoon://jobs-panel?action=toggle"
  else
    txt="$("$EC" down 2>&1 | head -12)"
    /usr/bin/osascript -e 'on run a' -e 'display notification (item 1 of a) with title "Jobs down"' -e 'end run' "$txt" >/dev/null 2>&1
  fi
  exit 0
fi

# Who watches the watcher: the collector rewrites down.json every 5 min. If the
# file is missing or over 20 min old, the collector itself is down and nothing
# else would say so, so the pill says it.
age=99999
[ -f "$F" ] && age=$(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$F") ))
if [ "$age" -gt 1200 ]; then
  $SB --set "$NAME" drawing=on label="checker down" icon.color="$RED"
  exit 0
fi

n=0
[ -f "$F" ] && n="$(/usr/bin/python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("down", [])))' "$F" 2>/dev/null)"
if [ "${n:-0}" -gt 0 ]; then
  $SB --set "$NAME" drawing=on label="$n down" icon.color="$RED"
else
  $SB --set "$NAME" drawing=off
fi
