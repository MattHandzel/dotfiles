#!/usr/bin/env bash
# leader-timer — start an N-minute countdown that notifies on start and finish.
#
# Backs the SUPER+SHIFT+SPACE "leader" submap (press leader, release, press a
# digit): Saul's seamless, no-context-switch timer he sets dozens of times a
# day. The submap calls "leader-timer <N>"; the digit 0 maps to 10 minutes.
set -euo pipefail

mins="${1:?usage: leader-timer MINUTES}"
case "$mins" in (*[!0-9]* | '') echo "minutes must be a non-negative integer" >&2; exit 2 ;; esac

notify-send -t 2000 -i alarm-clock "⏱ Timer started" "${mins} min"

# Detach so the countdown outlives the keybind's short-lived shell. Audible cue
# is best-effort: canberra if present, else a paplay fallback, else silent.
setsid -f bash -c "
  sleep $((mins * 60))
  notify-send -u critical -i alarm-clock '⏱ Timer done' '${mins} min elapsed'
  if command -v canberra-gtk-play >/dev/null 2>&1; then
    canberra-gtk-play -i complete >/dev/null 2>&1 || true
  elif command -v paplay >/dev/null 2>&1; then
    paplay /run/current-system/sw/share/sounds/freedesktop/stereo/complete.oga >/dev/null 2>&1 || true
  fi
" >/dev/null 2>&1
