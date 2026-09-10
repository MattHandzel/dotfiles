#!/usr/bin/env bash
# Today's next event — "14:00 Standup" — or the one running now, prefixed "now".
#
# Source 1: ~/.local/state/focus/agenda.json, written every 5 min by the
#           calendar-agenda launchd agent (read-only Google token, all
#           calendars). Same file waybar used on the laptop.
# Source 2: icalBuddy against Calendar.app, if the agenda file is missing or
#           older than 20 minutes.
# Nothing left today → the item hides itself.

SB=/opt/homebrew/bin/sketchybar
JQ=/opt/homebrew/bin/jq
AGENDA="$HOME/.local/state/focus/agenda.json"
ICALBUDDY=/opt/homebrew/bin/icalBuddy

label=""
prefix=""

fresh() { # file newer than 20 min
  [ -f "$1" ] && [ "$(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$1") ))" -lt 1200 ]
}

if fresh "$AGENDA"; then
  # Prefer what is happening now; else the next thing that starts today.
  today="$(/bin/date '+%Y-%m-%d')"
  read -r prefix label < <($JQ -r --arg today "$today" '
    def local: (.start | sub("\\.[0-9]+"; "") | fromdateiso8601);
    if (.now // empty) and (.now.title // "") != "" then
      "now\t" + .now.title
    else
      ([ (.next // empty), (.upcoming // [])[] ]
        | map(select(.start != null))
        | map(select((.start | sub("\\.[0-9]+"; "") | fromdateiso8601 | strflocaltime("%Y-%m-%d")) == $today))
        | first // empty)
      | (.start | sub("\\.[0-9]+"; "") | fromdateiso8601 | strflocaltime("%H:%M")) + "\t" + .title
    end' "$AGENDA" 2>/dev/null | head -1 | tr '\t' ' ')
  # `read` split on the first space: prefix = "now" or "HH:MM", label = title.
fi

if [ -z "$label" ] && [ -x "$ICALBUDDY" ]; then
  # -n: only events that have not ended yet. One line: "HH:MM Title".
  out="$($ICALBUDDY -n -nc -nrd -npn -ea -li 1 -b '' -ps '| |' -iep 'datetime,title' -po 'datetime,title' \
          -df '' -tf '%H:%M' eventsToday 2>/dev/null | head -1)"
  if [ -n "$out" ]; then
    prefix="${out%% *}"
    label="${out#* }"
    # "HH:MM - HH:MM Title" → keep the start only.
    label="$(printf '%s' "$label" | sed -E 's/^- [0-9]{2}:[0-9]{2} //')"
  fi
fi

if [ -z "$label" ]; then
  $SB --set "$NAME" drawing=off
else
  $SB --set "$NAME" drawing=on label="$prefix  $label"
fi
