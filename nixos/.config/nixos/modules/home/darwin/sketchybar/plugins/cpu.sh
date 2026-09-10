#!/usr/bin/env bash
# CPU as a whole-machine percentage. Sums per-process %cpu over the core count,
# which is instant (the alternative, `top -l 2`, blocks for a second).
ncpu="$(/usr/sbin/sysctl -n hw.ncpu)"
pct="$(/bin/ps -A -o %cpu= | /usr/bin/awk -v n="$ncpu" '{s+=$1} END {printf "%d", (s/n)+0.5}')"
[ "$pct" -gt 100 ] && pct=100
/opt/homebrew/bin/sketchybar --set "$NAME" label="${pct}%"
