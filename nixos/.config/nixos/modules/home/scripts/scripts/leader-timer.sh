#!/usr/bin/env bash
# leader-timer — start an N-minute countdown that notifies on start and finish.
#
# Backs the SUPER+SHIFT+SPACE "leader" submap (press leader, release, press a
# digit): Saul's seamless, no-context-switch timer he sets dozens of times a
# day. The submap calls "leader-timer <N>"; the digit 0 maps to 10 minutes.
# The Vicinae palette's "Timer (minutes)" command calls the same entry point.
#
#   leader-timer 15                 start a 15 minute timer
#   leader-timer 25 deep work       ... labelled "deep work"
#   leader-timer --list             show pending timers (with their labels)
#   leader-timer --cancel [UNIT]    cancel one timer, or all of them
#
# Timers are independent transient systemd units, so any number can run at once
# — the unit name carries minutes + label + start-second + PID, which is unique
# even for two identical timers started in the same second.
#
# macOS: the same shape on launchd. Each timer is a throwaway LaunchAgent plist
# under ~/Library/Caches/leader-timer (label = the unit name) that sleeps, then
# notifies (terminal-notifier) and plays a system sound, then boots itself out.
# A launchd job survives Raycast/skhd/AeroSpace reaping the caller's process
# group, which a plain `sleep … &` would not.
set -euo pipefail

if [[ "$(uname)" == Darwin ]]; then
  LT_DIR="$HOME/Library/Caches/leader-timer"
  mkdir -p "$LT_DIR"
  NOTIFY="$(command -v terminal-notifier || true)"
  SOUND_FILE=/System/Library/Sounds/Glass.aiff
  _uid="$(id -u)"

  mac_units() { local f; for f in "$LT_DIR"/*.plist; do [[ -e "$f" ]] || continue; basename "$f" .plist; done; }

  case "${1:-}" in
    --list)
      units=$(mac_units)
      [[ -n "$units" ]] || { echo "no timers pending"; exit 0; }
      now=$(date +%s)
      printf '%-6s  %-40s  %s\n' "LEFT" "WHAT" "UNIT"
      while IFS= read -r u; do
        what=$(cat "$LT_DIR/$u.what" 2>/dev/null || echo "$u")
        deadline=$(cat "$LT_DIR/$u.deadline" 2>/dev/null || echo "")
        if [[ "$deadline" == *[0-9]* && "$deadline" != *[!0-9]* ]]; then
          left=$((deadline - now)); ((left < 0)) && left=0
          left=$(printf '%d:%02d' $((left / 60)) $((left % 60)))
        else left="-"; fi
        printf '%-6s  %-40.40s  %s\n' "$left" "$what" "$u"
      done <<<"$units"
      exit 0
      ;;
    --cancel)
      cancel_one() {
        launchctl bootout "gui/$_uid/$1" 2>/dev/null || true
        rm -f "$LT_DIR/$1.plist" "$LT_DIR/$1.what" "$LT_DIR/$1.deadline"
      }
      if [[ -n "${2:-}" ]]; then
        cancel_one "$2"; echo "cancelled $2"
      else
        units=$(mac_units)
        [[ -n "$units" ]] || { echo "no timers running"; exit 0; }
        n=0; while IFS= read -r u; do cancel_one "$u"; n=$((n + 1)); done <<<"$units"
        echo "cancelled $n timer(s)"
      fi
      exit 0
      ;;
    "" | -h | --help) echo "usage: leader-timer MINUTES [LABEL...] | --list | --cancel [UNIT]" >&2; exit 2 ;;
  esac

  mins="$1"
  case "$mins" in (*[!0-9]* | '') echo "minutes must be a non-negative integer" >&2; exit 2 ;; esac
  shift
  label="$*"; label="${label#"${label%%[![:space:]]*}"}"; label="${label%"${label##*[![:space:]]}"}"
  what="${mins} min"; [[ -n "$label" ]] && what+=" — ${label}"
  title="⏱ Timer done"; [[ -n "$label" ]] && title+=" — ${label}"
  body="${mins} min elapsed"
  secs=$((mins * 60)); ((mins == 0)) && secs=1
  slug=""
  if [[ -n "$label" ]]; then
    slug=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-40)
    [[ -n "$slug" ]] && slug="-${slug}"
  fi
  unit="leader-timer-${mins}min${slug}-$(date +%s)-$$"
  plist="$LT_DIR/$unit.plist"
  printf '%s' "$what" >"$LT_DIR/$unit.what"
  printf '%s' "$(( $(date +%s) + secs ))" >"$LT_DIR/$unit.deadline"

  # The finishing script: title/body/paths arrive as environment, never
  # interpolated into the command string (labels are free text).
  finish='sleep "$LT_SECS"; if [ -n "$LT_NOTIFY" ]; then "$LT_NOTIFY" -title "$LT_TITLE" -message "$LT_BODY" -sound default >/dev/null 2>&1 || true; else /usr/bin/osascript -e "display notification \"$LT_BODY\" with title \"$LT_TITLE\""; fi; [ -r "$LT_SOUND" ] && /usr/bin/afplay "$LT_SOUND" >/dev/null 2>&1 || true; rm -f "$LT_PLIST" "${LT_PLIST%.plist}.what" "${LT_PLIST%.plist}.deadline"; launchctl bootout "gui/$(id -u)/$LT_UNIT" >/dev/null 2>&1 || true'

  xml_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' <<<"$1"; }
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$unit</string>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>-c</string><string>$(xml_escape "$finish")</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>LT_SECS</key><string>$secs</string>
    <key>LT_NOTIFY</key><string>$NOTIFY</string>
    <key>LT_TITLE</key><string>$(xml_escape "$title")</string>
    <key>LT_BODY</key><string>$(xml_escape "$body")</string>
    <key>LT_SOUND</key><string>$SOUND_FILE</string>
    <key>LT_PLIST</key><string>$plist</string>
    <key>LT_UNIT</key><string>$unit</string>
  </dict>
</dict></plist>
PLIST
  launchctl bootstrap "gui/$_uid" "$plist"
  [[ -n "$NOTIFY" ]] && "$NOTIFY" -title "⏱ Timer started" -message "$what" >/dev/null 2>&1 || true
  exit 0
fi

# Resolve helpers to absolute paths NOW, while we still have the caller's PATH.
# The countdown runs under the systemd user manager, whose PATH is nearly empty
# — the same gap that stopped Vicinae launching anything (see vicinae.nix).
NOTIFY="$(command -v notify-send || true)"
SOUND_FILE=/run/current-system/sw/share/sounds/freedesktop/stereo/complete.oga
PLAYER="$(command -v pw-play || command -v paplay || command -v canberra-gtk-play || true)"

usage() { echo "usage: leader-timer MINUTES [LABEL...] | --list | --cancel [UNIT]" >&2; exit 2; }

case "${1:-}" in
  --list)
    mapfile -t units < <(systemctl --user list-units --all --plain --no-legend 'leader-timer-*.timer' | awk '{print $1}')
    ((${#units[@]})) || { echo "no timers pending"; exit 0; }
    now=$(date +%s)
    printf '%-6s  %-40s  %s\n' "LEFT" "WHAT" "UNIT"
    for u in "${units[@]}"; do
      # Description is "leader-timer 25 min — deep work"; strip the prefix so the
      # WHAT column shows what Matt actually typed.
      what=$(systemctl --user show -p Description --value "$u" 2>/dev/null)
      what="${what#leader-timer }"
      # Remaining time comes from the wall-clock deadline we stamped into the
      # service at creation, NOT from systemd's NextElapse*. An --on-active timer
      # is monotonic, so NextElapseUSecRealtime is always empty, and the
      # monotonic value cannot be compared against /proc/uptime (uptime counts
      # suspend, CLOCK_MONOTONIC does not — hours apart on a laptop that sleeps).
      env=$(systemctl --user show -p Environment --value "${u%.timer}.service" 2>/dev/null)
      deadline="${env##*LT_DEADLINE=}"
      deadline="${deadline%% *}"
      if [[ "$deadline" == *[0-9]* && "$deadline" != *[!0-9]* ]]; then
        left=$((deadline - now))
        ((left < 0)) && left=0
        left=$(printf '%d:%02d' $((left / 60)) $((left % 60)))
      else
        left="-"
      fi
      printf '%-6s  %-40.40s  %s\n' "$left" "$what" "$u"
    done
    exit 0
    ;;
  --cancel)
    if [[ -n "${2:-}" ]]; then
      systemctl --user stop "$2" 2>/dev/null || true
      echo "cancelled $2"
    else
      mapfile -t units < <(systemctl --user list-units --all --plain --no-legend 'leader-timer-*.timer' | awk '{print $1}')
      ((${#units[@]})) || { echo "no timers running"; exit 0; }
      systemctl --user stop "${units[@]}" 2>/dev/null || true
      echo "cancelled ${#units[@]} timer(s)"
    fi
    exit 0
    ;;
  "" | -h | --help) usage ;;
esac

mins="$1"
case "$mins" in (*[!0-9]* | '') echo "minutes must be a non-negative integer" >&2; exit 2 ;; esac
shift

# Everything after the minutes is the optional label — unquoted is fine, so
# `leader-timer 25 deep work on MAT-1462` works without shell quoting.
label="$*"
label="${label#"${label%%[![:space:]]*}"}"  # trim leading space
label="${label%"${label##*[![:space:]]}"}"  # trim trailing space

what="${mins} min"
[[ -n "$label" ]] && what+=" — ${label}"

[[ -n "$NOTIFY" ]] && "$NOTIFY" -t 2000 -i alarm-clock "⏱ Timer started" "$what"

# systemd owns the countdown, NOT a backgrounded subshell. `setsid -f` was not
# enough: Vicinae reaps the process group of a script it ran the moment that
# script exits — even through setsid/nohup — so a timer set from the palette was
# killed instantly and silently never fired (the same trap that killed the
# white-noise player, see vicinae.nix). A transient systemd timer lives in its
# own cgroup, outside any launcher's lifecycle, so it survives the palette, the
# keybind shell, and the terminal alike.
#
# The finish notification sets SWAYNC_BYPASS_DND: a timer Matt deliberately set
# is precisely the notification that should still reach him in Do Not Disturb.
# It is also urgency=critical, which swaync renders with no timeout.
delay="${mins}min"
((mins == 0)) && delay="1s"

title="⏱ Timer done"
[[ -n "$label" ]] && title+=" — ${label}"
body="${mins} min elapsed"

# The title/body travel as unit environment, NOT interpolated into the bash -c
# string. A label is free text — "Bob's 1:1" would otherwise close the single
# quote and mangle (or break) the notification command.
cmd=""
[[ -n "$NOTIFY" ]] && cmd+="'$NOTIFY' -u critical -i alarm-clock -h boolean:SWAYNC_BYPASS_DND:true \"\$LT_TITLE\" \"\$LT_BODY\"; "
[[ -n "$PLAYER" && -r "$SOUND_FILE" ]] && cmd+="'$PLAYER' '$SOUND_FILE' >/dev/null 2>&1 || true"
[[ -n "$cmd" ]] || { echo "leader-timer: no notify-send and no audio player available" >&2; exit 1; }

# Slugify the label into the unit name so --list/--cancel stay readable.
slug=""
if [[ -n "$label" ]]; then
  slug=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-40)
  [[ -n "$slug" ]] && slug="-${slug}"
fi

systemd-run --user --collect --quiet \
  --unit "leader-timer-${mins}min${slug}-$(date +%s)-$$" \
  --description "leader-timer ${what}" \
  --setenv=LT_TITLE="$title" \
  --setenv=LT_BODY="$body" \
  --setenv=LT_DEADLINE="$(( $(date +%s) + mins * 60 ))" \
  --on-active="$delay" \
  --timer-property=AccuracySec=1s \
  bash -c "$cmd"
