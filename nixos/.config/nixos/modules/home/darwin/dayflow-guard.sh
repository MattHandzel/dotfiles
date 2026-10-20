#!/usr/bin/env bash
# dayflow-guard — keep Dayflow's screenshot interval at 1 s, and say so when
# Dayflow isn't actually saving a frame about every second while Matt is at
# the Mac.
#
# WHY: Matt, 2026-10-06 18:07: "Please prevent this from happening again where
# the interval is not 1 second. If it starts to be too much, then we can solve
# that problem when we get there." Dayflow's frames are the ground truth of
# the lifelog (scripts/lifelog, the lifelog skill). On 2026-10-05 an Oops
# session lowered the interval to 30 s as a stopgap for a degraded systemstatusd
# (system-problem-log, 2026-10-05 22:50). It stayed at 30 s for 19 h after the
# reboot that fixed the cause, and nothing said so. The same evening Dayflow
# saved no frame for 5 h (18:06-23:06) and nothing said that either.
#
# So, every 5 min and whenever Dayflow's preferences file changes:
#   1. screenshotIntervalSeconds != 1  -> write 1 back, log, and notify.
#   2. Matt active (HID idle < 2 min), Dayflow set to record, and the frames of
#      the last 3 min are missing or more than 3 s apart -> notify, at most
#      every 2 h per problem. This is the "it starts to be too much" signal.
#      If capture is slow, systemstatus-guard says whether a reboot is due.
#      Never lower the interval to fix it: that is Matt's call.
set -uo pipefail

DOMAIN="teleportlabs.com.Dayflow"
WANT=1
DB="$HOME/Library/Application Support/Dayflow/chunks.sqlite"
STATE_DIR="$HOME/.local/state/dayflow-guard"
NTFY_URL="http://server.matthandzel.com:8124/claude"
REPEAT_SECONDS=7200
mkdir -p "$STATE_DIR"
stamp="$(date -Iseconds)"

notify() { # <kind> <title> <body>; at most every REPEAT_SECONDS per kind
  local f="$STATE_DIR/last-$1" now last
  now="$(date +%s)"
  last="$(cat "$f" 2>/dev/null || echo 0)"
  [ $((now - last)) -lt "$REPEAT_SECONDS" ] && return 0
  echo "$now" >"$f"
  [ -n "${DAYFLOW_GUARD_DRY:-}" ] && { echo "  (dry run: would notify \"$2\")"; return 0; }
  /usr/bin/osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name "Funk"' -e 'end run' "$2" "$3" >/dev/null 2>&1 || true
  curl -fsS -m 5 -H "Title: $2" -H "Tags: camera,warning" -d "$3" "$NTFY_URL" >/dev/null 2>&1 || true
}

# 1. The setting.
cur="$(/usr/bin/defaults read "$DOMAIN" screenshotIntervalSeconds 2>/dev/null || echo unset)"
if ! awk -v c="$cur" -v w="$WANT" 'BEGIN { exit !(c == w) }'; then
  if [ -n "${DAYFLOW_GUARD_DRY:-}" ]; then
    echo "$stamp interval was $cur s (dry run: would set it to $WANT s)"
  else
    /usr/bin/defaults write "$DOMAIN" screenshotIntervalSeconds -float "$WANT"
    echo "$stamp interval was $cur s, set back to $WANT s"
    notify interval "Dayflow interval reset to ${WANT} s" \
      "Something set Dayflow's screenshot interval to $cur s. It is back at ${WANT} s, your rule from 2026-10-06. Log: ~/.local/state/dayflow-guard.log"
    cur="$WANT"
  fi
fi

# 2. The frames. Only while Matt is at the Mac and Dayflow is meant to record.
idle="$(/usr/sbin/ioreg -c IOHIDSystem | awk '/HIDIdleTime/ { print int($NF / 1000000000); exit }')"
recording="$(/usr/bin/defaults read "$DOMAIN" isRecording 2>/dev/null || echo 1)"
if [ "${idle:-0}" -ge 120 ] || [ "$recording" != "1" ]; then
  echo "$stamp ok interval=${cur}s idle=${idle}s recording=$recording (frames not checked)"
  exit 0
fi
running=yes
/usr/bin/pgrep -xq Dayflow || running=no

# created_at is UTC insert time, one row per frame as it is saved.
read -r n median < <(/usr/bin/sqlite3 -readonly "$DB" \
  "select strftime('%s', created_at) from screenshots where created_at > datetime('now', '-180 seconds') order by created_at" 2>/dev/null |
  awk 'NR > 1 { d[m++] = $1 - p } { p = $1; n++ }
       END { if (m == 0) { printf "%d 0\n", n; exit }
             for (i = 0; i < m; i++) for (j = i + 1; j < m; j++) if (d[j] < d[i]) { t = d[i]; d[i] = d[j]; d[j] = t }
             printf "%d %d\n", n, d[int((m - 1) / 2)] }')
n="${n:-0}"
echo "$stamp interval=${cur}s idle=${idle}s running=$running frames_3min=$n median_gap=${median:-0}s"

if [ "$running" = no ]; then
  notify stopped "Dayflow isn't running" "You're at the Mac but Dayflow isn't running, so nothing is being recorded. Open it from Raycast or Spotlight."
elif [ "$n" -eq 0 ]; then
  notify stopped "Dayflow isn't saving frames" "You're at the Mac and Dayflow is set to record, but it saved no frame in the last 3 minutes. Check that Dayflow shows Recording."
elif [ "${median:-0}" -gt 3 ]; then
  notify slow "Dayflow is capturing every ${median} s, not ${WANT} s" "Screen capture may be backed up (system-problem-log, 2026-10-05 22:50). systemstatus-guard will say if a reboot is due. The interval was left at ${WANT} s."
else
  rm -f "$STATE_DIR/last-stopped" "$STATE_DIR/last-slow"
fi
