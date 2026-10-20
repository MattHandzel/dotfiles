#!/usr/bin/env bash
# disk-space-alert (macOS port of modules/core/disk-space-alert.nix +
# Obsidian/Main/scripts/disk-space-alert.sh).
#
# WHY A PORT AND NOT THE ORIGINALS:
#   * the NixOS unit ran as root against /home and / with a state file in
#     /var/lib; on the Mac this is a *user* LaunchAgent, so state lives under
#     ~/.local/state.
#   * both originals call `df --block-size=1G --output=avail`. BSD df on macOS
#     has neither flag. Use `df -k -P` and convert: -P is POSIX output, and it
#     FORCES 512-byte blocks, silently overriding a -g. (`df -g -P` reports
#     388514104 "GiB" free — 512-byte blocks wearing a -g label. Verified
#     against `df -h`: -k -P then /1048576 gives the right number.)
#   * on macOS the home directory and the root filesystem are two volumes of
#     ONE APFS container sharing a single free-space pool, so checking
#     /System/Volumes/Data is the meaningful number; "/" reports the same pool.
#
# Debounced exactly like the Linux version: notify only when the level CHANGES,
# so a genuinely full disk pings once, not every 15 minutes.
set -uo pipefail

NTFY_URL="http://server.matthandzel.com:8124/claude"
STATE_DIR="$HOME/.local/state/disk-space-alert"
STATE_FILE="$STATE_DIR/last-alert-level"

# Higher than the NixOS unit (20/5). macOS swap lives on this same pool and
# grows in 1 GiB files; at 5 GiB free it already could not grow and apps were
# paused ("out of application memory", Oops 2026-09-15 10:28). 15 GiB is the
# swap headroom this 32 GB machine used that morning (9 GiB) plus margin.
WARN_GIB=40
URGENT_GIB=15
# Matt, 2026-10-06: "lets me know when I have less than 10 GB of storage
# remaining so that I can work on this". Dayflow has saved a frame every 1 s
# since that day (dayflow-guard.nix), about 0.5 GB a day, and nothing deletes
# them. So 10 GiB is its own level, and every alert says how big Dayflow is
# and how fast it grows.
CRITICAL_GIB=10
DAYFLOW_DIR="$HOME/Library/Application Support/Dayflow/recordings"
DAYFLOW_SIZES="$STATE_DIR/dayflow-sizes" # "<YYYY-MM-DD> <KiB>", one line a day

mkdir -p "$STATE_DIR"

prev_level="none"
[ -f "$STATE_FILE" ] && prev_level="$(cat "$STATE_FILE")"

# -k -P = POSIX one-line-per-fs output in 1 KiB blocks. Field 4 = available.
avail_gib="$(/bin/df -k -P /System/Volumes/Data | tail -1 | awk '{printf "%d", $4/1048576}')"
root_gib="$(/bin/df -k -P / | tail -1 | awk '{printf "%d", $4/1048576}')"

case "$avail_gib" in
  '' | *[!0-9]*)
    echo "disk-space-alert: could not parse df output" >&2
    exit 1
    ;;
esac

current_level="none"
if [ "$avail_gib" -lt "$CRITICAL_GIB" ]; then
  current_level="critical"
elif [ "$avail_gib" -le "$URGENT_GIB" ]; then
  current_level="urgent"
elif [ "$avail_gib" -le "$WARN_GIB" ]; then
  current_level="warn"
fi

echo "$(date -Iseconds) data=${avail_gib}G root=${root_gib}G level=$current_level prev=$prev_level"

# Dayflow's size, sampled once a day, and its growth over the last week.
dayflow_kib="$(/usr/bin/du -sk "$DAYFLOW_DIR"/ 2>/dev/null | awk '{print $1}')"
dayflow_note=""
if [ -n "$dayflow_kib" ]; then
  today="$(date +%F)"
  grep -q "^$today " "$DAYFLOW_SIZES" 2>/dev/null || echo "$today $dayflow_kib" >>"$DAYFLOW_SIZES"
  dayflow_note="$(tail -8 "$DAYFLOW_SIZES" | awk -v now="$dayflow_kib" '
    NR == 1 { first = $2; d0 = $1 } { d1 = $1 }
    END {
      cmd = "date -d " d0 " +%s"; cmd | getline a; close(cmd)
      cmd = "date -d " d1 " +%s"; cmd | getline b; close(cmd)
      days = (b - a) / 86400
      s = sprintf("Dayflow recordings: %.1f GB", now / 1048576)
      if (days >= 1) s = s sprintf(", growing %.2f GB/day", (now - first) / 1048576 / days)
      print s "."
    }')"
fi
echo "${dayflow_note:-Dayflow recordings: unknown}"

# Urgent: reclaim regenerable caches on every run (idempotent, cheap when
# empty). On 2026-09-15 this gave back 11 GiB (Homebrew 9.5, uv 1.8).
if [ "$current_level" = "urgent" ] || [ "$current_level" = "critical" ]; then
  HOMEBREW_NO_AUTO_UPDATE=1 /opt/homebrew/bin/brew cleanup --prune=all -s 2>&1 | tail -1
  "$HOME/.nix-profile/bin/uv" cache prune 2>&1 | tail -1
  avail_gib="$(/bin/df -k -P /System/Volumes/Data | tail -1 | awk '{printf "%d", $4/1048576}')"
  echo "after cache cleanup: data=${avail_gib}G"
fi

# ntfy alone was not enough: the server timed out on every alert that morning
# (curl: (28)), so Matt saw nothing. Also post a local notification.
local_notify() {
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
}

# ── Runaway log detection ────────────────────────────────────────────────────
# The free-space thresholds above are absolute, and a file growing slowly
# stays under them for months: ~/Projects/website/sync.log reached 40 GB
# (2026-09-16) without this script ever having a reason to speak. So also
# watch the RATE. Every launchd log we write lives in one of LOG_DIRS; sizes
# from the previous tick are kept in $SIZES_FILE as "<bytes> <path>" lines,
# and a file that grew more than GROWTH_GIB since then (15 minutes ago), or
# just crossed BIG_GIB outright, gets an alert that names it. Crossing is
# detected against the previous size, so a big-but-stable file pings once.
GROWTH_GIB=1
BIG_GIB=5
SIZES_FILE="$STATE_DIR/log-sizes"
LOG_DIRS=("$HOME/.local/state" "$HOME/.local/log" "$HOME/Library/Logs" "$HOME/Projects/website")

check_log_growth() {
  local next="$SIZES_FILE.next" msg="" path size old
  local growth_bytes=$((GROWTH_GIB * 1073741824)) big_bytes=$((BIG_GIB * 1073741824))
  : > "$next"
  while IFS= read -r path; do
    size="$(/usr/bin/stat -f %z "$path" 2>/dev/null)" || continue
    printf '%s %s\n' "$size" "$path" >> "$next"
    old=""
    [ -f "$SIZES_FILE" ] && old="$(awk -v p="$path" 'substr($0, index($0, " ") + 1) == p {print $1; exit}' "$SIZES_FILE")"
    if [ -n "$old" ] && [ $((size - old)) -gt "$growth_bytes" ]; then
      msg="$msg$path grew $(( (size - old) / 1048576 )) MiB in the last 15 min. "
    elif [ "$size" -gt "$big_bytes" ] && [ "${old:-0}" -le "$big_bytes" ]; then
      msg="$msg$path is $(( size / 1073741824 )) GiB. "
    fi
  done < <(/usr/bin/find "${LOG_DIRS[@]}" -maxdepth 1 -type f -name '*.log*' 2>/dev/null)
  mv -f "$next" "$SIZES_FILE"

  [ -z "$msg" ] && return 0
  echo "runaway log: $msg"
  local_notify "Runaway log file" "$msg"
  curl -sS --max-time 15 \
    -H "Title: Runaway log file" \
    -H "Priority: high" \
    -H "Tags: page_facing_up,warning" \
    -d "$(hostname -s): $msg" \
    "$NTFY_URL" >/dev/null || true
}
check_log_growth

if [ "$current_level" = "$prev_level" ]; then
  echo "Disk level unchanged ($current_level). No notification."
  exit 0
fi

echo "$current_level" > "$STATE_FILE"

host="$(hostname -s)"

if [ "$current_level" = "none" ]; then
  curl -sS --max-time 15 \
    -H "Title: Disk Space OK" \
    -H "Priority: low" \
    -H "Tags: white_check_mark" \
    -d "$host: disk space recovered. ${avail_gib}G free." \
    "$NTFY_URL" >/dev/null || true
  exit 0
fi

if [ "$current_level" = "critical" ]; then
  priority="urgent"; title="Under ${CRITICAL_GIB} GB free: time to deal with Dayflow's recordings"; tags="rotating_light"
elif [ "$current_level" = "urgent" ]; then
  priority="urgent"; title="URGENT: Disk space critically low"; tags="rotating_light"
else
  priority="high"; title="Disk space warning"; tags="warning"
fi

local_notify "$title" "${avail_gib}G free. Below ${URGENT_GIB}G macOS cannot grow swap and pauses apps. ${dayflow_note} Biggest: /Volumes/LinuxHome, ~/Projects, ~/Videos."

curl -sS --max-time 15 \
  -H "Title: $title" \
  -H "Priority: $priority" \
  -H "Tags: $tags" \
  -d "$host: ${avail_gib}G free on the data volume (root reports ${root_gib}G). ${dayflow_note}" \
  "$NTFY_URL" >/dev/null || true

echo "Sent $current_level notification."
