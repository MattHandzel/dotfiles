#!/usr/bin/env bash
# glucose — show Matt's current CGM reading in the terminal (MAT-1720).
#
# Reads the PUBLIC health-stream endpoint, so there is no secret to manage on
# this machine: the full series is published by design (Matt's 2026-07-24
# decision), and the same URL backs the widget on the website.
#
# The honest-freshness rule this inherits from the server: Abbott publishes
# Lingo readings to Health Connect on a ~3 HOUR delay. "12 min ago" here means
# the newest READING's own timestamp, not when we fetched it — so a healthy
# pipeline still shows a couple of hours of age. That is the sensor, not a bug.
#
# Exit codes are meaningful for scripting:
#   0  a reading was printed
#   1  reachable but no readings in the window (sensor off / sync stopped)
#   2  the service is unreachable or returned an error
set -euo pipefail

BASE="${HEALTH_STREAM_URL:-https://health-stream-black.vercel.app}"
HOURS="${1:-24}"

if ! [[ "$HOURS" =~ ^[0-9]+$ ]]; then
  echo "usage: glucose [hours]   (default 24)" >&2
  exit 2
fi

# --fail so an HTTP error is a non-zero exit rather than an error body parsed as
# data; a bounded timeout so a hung service can't wedge a shell prompt.
if ! body=$(curl -sS --fail --max-time 8 "$BASE/api/public/glucose?hours=$HOURS" 2>/dev/null); then
  echo "glucose: health-stream unreachable ($BASE)" >&2
  exit 2
fi

# All formatting happens in one jq pass. Anything the server reports as absent
# stays absent — the CLI never substitutes a zero for a missing reading.
printf '%s' "$body" | jq -r '
  def bar(v): (((v - 55) / 145 * 24) | floor | if . < 0 then 0 elif . > 24 then 24 else . end) as $n
    | ("█" * $n) + ("·" * (24 - $n));
  def age(s):
    if s == null then "unknown"
    elif s < 60 then "just now"
    elif s < 3600 then "\((s/60)|floor) min ago"
    else "\((s/3600)|floor)h \(((s%3600)/60)|floor)m ago" end;
  def arrow(t): if t == "rising" then "↑" elif t == "falling" then "↓" elif t == "flat" then "→" else " " end;

  if (.summary.latest == null) then
    "no readings in the last \(.range.hours)h\n" | halt_error(1)
  else
    "\(.summary.latest.mgdl | round) mg/dL \(arrow(.summary.trend))" +
      (if .summary.delta_mgdl != null then " \(if .summary.delta_mgdl > 0 then "+" else "" end)\(.summary.delta_mgdl | round)" else "" end) +
      (if .summary.latest.clamped then "  [at sensor limit]" else "" end) + "\n" +
    "  \(bar(.summary.latest.mgdl))  \(age(.freshness.age_seconds))" +
      (if .freshness.stale then "  ⚠ STALE — sync may have stopped" else "" end) + "\n" +
    "  \(.range.hours)h  avg \(.summary.mean_mgdl)  min \(.summary.min_mgdl)  max \(.summary.max_mgdl)  n=\(.summary.count)"
  end
'
