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

# Same thresholds as the NixOS unit (GiB free).
WARN_GIB=20
URGENT_GIB=5

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
if [ "$avail_gib" -le "$URGENT_GIB" ]; then
  current_level="urgent"
elif [ "$avail_gib" -le "$WARN_GIB" ]; then
  current_level="warn"
fi

echo "$(date -Iseconds) data=${avail_gib}G root=${root_gib}G level=$current_level prev=$prev_level"

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

if [ "$current_level" = "urgent" ]; then
  priority="urgent"; title="URGENT: Disk space critically low"; tags="rotating_light"
else
  priority="high"; title="Disk space warning"; tags="warning"
fi

curl -sS --max-time 15 \
  -H "Title: $title" \
  -H "Priority: $priority" \
  -H "Tags: $tags" \
  -d "$host: ${avail_gib}G free on the data volume (root reports ${root_gib}G)." \
  "$NTFY_URL" >/dev/null || true

echo "Sent $current_level notification."
