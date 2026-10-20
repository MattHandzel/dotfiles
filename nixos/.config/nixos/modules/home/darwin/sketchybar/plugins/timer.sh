#!/usr/bin/env bash
# Timer pill: "⏱ 4:07 brain dump" while a leader-timer countdown is pending
# (Raycast "Timer (minutes)", the AeroSpace leader digits, the Work Test);
# hidden when none is. The soonest timer is shown, "+N" counts the others.
# Clicking the pill opens a popup listing every timer, soonest first.
# Remaining time reads "1h 05m" from an hour up and "4:07" (m:ss) below it;
# the item ticks every second while any timer is under an hour.
#
# Added 2026-10-14 (Oops 20261014-132219): Raycast "timer 5 brain dump" was
# closed with ⎋ instead of ↩, so it never ran, and nothing on screen showed
# that no timer was running (Do Not Disturb holds the "Timer started" banner)
# until the alarm failed to come 12 minutes later: "my timers are not working".
#
# Reads leader-timer's own state, ~/Library/Caches/leader-timer/<unit>.deadline
# (epoch) and .what ("25 min — brain dump"). Refreshed every 5 s and on the
# `timer_update` event, which leader-timer fires on start, cancel and finish.
#
# Popup + h:m / m:ss format added 2026-10-18 (Oops 20261018-164056) at Matt's
# request: with several timers only the soonest was visible.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"
SB=/opt/homebrew/bin/sketchybar
DIR="$HOME/Library/Caches/leader-timer"

fmt() {
  local s=$1
  if [ "$s" -ge 3600 ]; then
    printf '%dh %02dm' $((s / 3600)) $((s % 3600 / 60))
  else
    printf '%d:%02d' $((s / 60)) $((s % 60))
  fi
}

case "$SENDER" in
  mouse.clicked) "$CONFIG_DIR/plugins/bfy_click.sh"; $SB --set "$NAME" popup.drawing=toggle; exit 0 ;;
  mouse.exited.global) $SB --set "$NAME" popup.drawing=off; exit 0 ;;
esac

now=$(date +%s)
# One "deadline<TAB>label" line per pending timer, soonest first.
rows=$(
  for f in "$DIR"/*.deadline; do
    [ -e "$f" ] || continue
    d=$(cat "$f" 2>/dev/null)
    case "$d" in ('' | *[!0-9]*) continue ;; esac
    what=$(cat "${f%.deadline}.what" 2>/dev/null)
    case "$what" in (*" — "*) what=${what#* — } ;; (*) what="" ;; esac
    printf '%s\t%s\n' "$d" "$what"
  done | sort -n
)

# Rows are rebuilt only when the number of timers changes, so the open popup
# does not flicker on the 1 s tick.
have=$($SB --query "$NAME" 2>/dev/null | grep -c '"timer\.row\.')
want=0
[ -n "$rows" ] && want=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
[ "$have" -ne "$want" ] && $SB --remove '/timer\.row\..*/' >/dev/null 2>&1
if [ "$want" -eq 0 ]; then
  $SB --set "$NAME" drawing=off popup.drawing=off update_freq=5
  exit 0
fi

n=0 label="" freq=30 args=()
while IFS=$'\t' read -r d what; do
  left=$((d - now))
  [ "$left" -lt 0 ] && left=0
  [ "$left" -lt 3600 ] && freq=1
  t=$(fmt "$left")
  if [ "$n" -eq 0 ]; then
    label="$t${what:+ $what}"
  fi
  [ "$have" -ne "$want" ] && args+=(--add item "timer.row.$n" popup."$NAME")
  args+=(--set "timer.row.$n" icon="$t" icon.color="$PEACH" icon.width=64
    label="${what:-timer}" label.color="$TEXT")
  n=$((n + 1))
done <<<"$rows"

[ "$n" -gt 1 ] && label="$label +$((n - 1))"
$SB --set "$NAME" drawing=on label="$label" update_freq=$freq "${args[@]}"
