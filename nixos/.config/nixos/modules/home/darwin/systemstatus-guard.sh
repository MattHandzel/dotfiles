#!/usr/bin/env bash
# systemstatus-guard — warn before macOS's privacy-indicator daemon gets slow
# enough to break the camera in a video call.
#
# WHY (Oops 2026-10-06 14:12): the built-in camera failed at the start of the
# Kairos interview (Google Meet in Dia, 12:45). The hardware streamed within
# 1 s, but an app only gets its camera once `systemstatusd` (the daemon behind
# the green camera dot) has accepted the "camera in use" attribution, and after
# 8 days of uptime each attribution update took 5-17 s. Dia's capture session
# reported "started" 10.1, 12.4 and 12.6 s after each request, Chromium's
# camera-start timeout had already fired, and Meet gave up after three tries.
# The 2026-10-05 22:50 problem-log entry had found the same degraded daemon
# (screenshots failing) and left "needs-matt: reboot"; nothing reminded Matt
# and the reboot came at 13:46, after the call.
#
# systemstatusd is SIP-protected: it cannot be killed or kickstarted, only a
# reboot resets it. So this job only measures and tells Matt.
#
# Measure: replayd publishes a screen-recording attribution start+stop to
# systemstatusd for every ScreenCaptureKit shot (Dayflow takes one every 30 s),
# and logs the request (`:115 … hasStarted=`) and its completion
# (`_block_invoke_2:136 … STMediaStatusDomainPublisher`). Updates are served in
# order, so pairing them FIFO gives the per-update latency. Healthy: 2-10 ms
# (fresh boot). 2026-10-05 22:40: 2.85 s. Interview: 4-17 s. A camera start
# waits for at least two updates (mic + cam), so warn at WARN_SECONDS, days
# before it reaches the ~10 s that breaks a call.
set -uo pipefail

WARN_SECONDS="${SYSTEMSTATUS_GUARD_WARN:-0.5}"
REPEAT_SECONDS=7200 # while degraded, remind at most every 2 h
STATE_DIR="$HOME/.local/state/systemstatus-guard"
NTFY_URL="http://server.matthandzel.com:8124/claude"
mkdir -p "$STATE_DIR"

# Test hook: SYSTEMSTATUS_GUARD_LOG=<file of `log show --style compact` lines>
# reads that file instead of the live log and prints instead of notifying.
if [ -n "${SYSTEMSTATUS_GUARD_LOG:-}" ]; then
  lines="$(cat "$SYSTEMSTATUS_GUARD_LOG")"
else
  lines="$(/usr/bin/log show --last 3m --style compact \
    --predicate 'process == "replayd" AND eventMessage CONTAINS "updateScreenCaptureDidStart"' 2>/dev/null)"
fi

# -> "<samples> <max seconds> <median seconds>"
read -r n max median < <(printf '%s\n' "$lines" | awk '
  function secs(t,  p) { split(t, p, ":"); return p[1] * 3600 + p[2] * 60 + p[3] }
  /hasStarted=/ && /:115 / { q[qt++] = secs($2); next }
  /_block_invoke_2:136/ && /STMediaStatusDomainPublisher/ {
    if (qh == qt) next # completion of a request from before the window
    d = secs($2) - q[qh++]
    if (d < 0) d += 86400 # midnight
    v[n++] = d
  }
  END {
    if (n == 0) { print 0, 0, 0; exit }
    for (i = 0; i < n; i++) for (j = i + 1; j < n; j++) if (v[j] < v[i]) { t = v[i]; v[i] = v[j]; v[j] = t }
    printf "%d %.3f %.3f\n", n, v[n - 1], v[int((n - 1) / 2)]
  }')

stamp="$(date -Iseconds)"
uptime_days="$(/usr/sbin/sysctl -n kern.boottime | awk -v now="$(date +%s)" '{gsub(",", ""); printf "%.1f", (now - $4) / 86400}')"

if [ "${n:-0}" -eq 0 ]; then
  echo "$stamp no replayd attribution updates in the last 3 min (Dayflow not capturing?); up ${uptime_days}d"
  exit 0
fi

echo "$stamp updates=$n max=${max}s median=${median}s up=${uptime_days}d"

if awk -v m="$max" -v w="$WARN_SECONDS" 'BEGIN { exit !(m < w) }'; then
  rm -f "$STATE_DIR/last-warned"
  exit 0
fi

now="$(date +%s)"
last="$(cat "$STATE_DIR/last-warned" 2>/dev/null || echo 0)"
[ $((now - last)) -lt "$REPEAT_SECONDS" ] && exit 0
echo "$now" >"$STATE_DIR/last-warned"

title="Reboot before your next video call"
body="macOS's camera-indicator service is slow (${max}s per update, healthy is under 0.05s; up ${uptime_days} days). Past ~5s, Meet/Zoom cannot start the camera. Only a reboot fixes it."
echo "$stamp WARN: $body"
[ -n "${SYSTEMSTATUS_GUARD_LOG:-}" ] && exit 0 # test run: no notification
/usr/bin/osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv) sound name "Funk"' -e 'end run' "$title" "$body" || true
curl -fsS -m 5 -H "Title: $title" -H "Priority: high" -H "Tags: camera,warning" -d "$body" "$NTFY_URL" >/dev/null 2>&1 || true
