#!/usr/bin/env bash
# What is running now and what is next — "Deep work → 14:00 personal brand".
#
# Source 1: ~/.local/state/focus/agenda.json, written every 5 min by the
#           calendar-agenda launchd agent (read-only Google token; only the
#           calendars FOCUS_AGENDA_INCLUDE names in
#           modules/home/darwin/automations.nix). Same file waybar used on the
#           laptop.
# Source 2: icalBuddy against Calendar.app, if the agenda file is missing or
#           older than 20 minutes.
# Nothing running and nothing left → the item hides itself.

SB=/opt/homebrew/bin/sketchybar
JQ=/opt/homebrew/bin/jq
AGENDA="$HOME/.local/state/focus/agenda.json"
ICALBUDDY=/opt/homebrew/bin/icalBuddy
# Same calendars as agendaIncludeCalendars in modules/home/darwin/automations.nix.
ICAL_CALENDARS="handzelmatthew@gmail.com,Generator Extension Calendar Core,Generator Extension Calendar Unofficial/Social,Life Scheduler,The Mil,Swapcard calendar"

# Each title is clipped on its own so the next event always survives the item's
# label.max_chars — clipping the joined string would drop it entirely.
NOW_MAX=13
NEXT_MAX=13

now_title=""
next_when=""
next_title=""

fresh() { # file newer than 20 min
  [ -f "$1" ] && [ "$(( $(/bin/date +%s) - $(/usr/bin/stat -f %m "$1") ))" -lt 1200 ]
}

clip() { # clip $1 to $2 characters, with an ellipsis when it had to cut
  local s=$1 n=$2
  if [ "${#s}" -gt "$n" ]; then printf '%s…' "${s:0:$((n - 1))}"; else printf '%s' "$s"; fi
}

if fresh "$AGENDA"; then
  # agenda.py writes offset timestamps ("…T19:00:00+00:00"); jq's
  # fromdateiso8601 only accepts a literal "Z", so parse the offset by hand.
  # (Feeding it the raw string errored out, which is why the "next event"
  # branch never rendered before 2026-09-20.)
  tsv="$($JQ -r '
    def epoch:
      (sub("\\.[0-9]+"; "")) as $t
      | (($t[0:19] + "Z") | fromdateiso8601) as $b
      | ($t[19:] | sub(":"; "")) as $o
      | if ($o | length) >= 5 and (($o[0:1] == "+") or ($o[0:1] == "-"))
        then $b - ((($o[1:3] | tonumber) * 3600 + ($o[3:5] | tonumber) * 60)
                   * (if $o[0:1] == "-" then -1 else 1 end))
        else $b end;
    # Bare "HH:MM" for something later today, "Sat 09:00" once it is another day.
    def when($today): epoch as $e
      | ($e | strflocaltime("%Y-%m-%d")) as $d
      | if $d == $today then ($e | strflocaltime("%H:%M"))
        else ($e | strflocaltime("%a %H:%M")) end;
    (now | strflocaltime("%Y-%m-%d")) as $today
    | [ (.now.title // ""),
        (if ((.next.start // "") != "") then (.next.start | when($today)) else "" end),
        (.next.title // "") ]
    | @tsv' "$AGENDA" 2>/dev/null)"
  # Split by hand: `read` with IFS=$'\t' silently drops a leading empty field
  # (tab counts as IFS whitespace), which shifted the columns left whenever
  # nothing was running and turned "\t15:30\tLunch" into now_title="15:30".
  if [ -n "$tsv" ]; then
    now_title="${tsv%%$'\t'*}"
    rest="${tsv#*$'\t'}"
    next_when="${rest%%$'\t'*}"
    next_title="${rest#*$'\t'}"
  fi
fi

if [ -z "$now_title" ] && [ -z "$next_title" ] && [ -x "$ICALBUDDY" ]; then
  # -n: only events that have not ended yet, so line 1 may be the running one.
  # Each line is "HH:MM Title" or "HH:MM - HH:MM Title".
  hhmm_now="$(/bin/date '+%H:%M')"
  # -li 3, not 2: two events can already be running, and a started event must
  # never be reported as the next one.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    t="${line%% *}"
    title="${line#* }"
    title="$(printf '%s' "$title" | sed -E 's/^- [0-9]{2}:[0-9]{2} //')"
    if [[ ! "$t" > "$hhmm_now" ]]; then         # already started → it is "now"
      [ -z "$now_title" ] && now_title="$title"
    elif [ -z "$next_title" ]; then
      next_when="$t"
      next_title="$title"
    fi
  done < <($ICALBUDDY -ic "$ICAL_CALENDARS" -n -nc -nrd -npn -ea -li 3 -b '' -ps '| |' -iep 'datetime,title' \
             -po 'datetime,title' -df '' -tf '%H:%M' eventsToday 2>/dev/null)
fi

label=""
[ -n "$now_title" ] && label="$(clip "$now_title" "$NOW_MAX")"
if [ -n "$next_title" ]; then
  [ -n "$label" ] && label="$label → "
  label="$label$next_when $(clip "$next_title" "$NEXT_MAX")"
fi

if [ -z "$label" ]; then
  $SB --set "$NAME" drawing=off
else
  $SB --set "$NAME" drawing=on label="$label"
fi
