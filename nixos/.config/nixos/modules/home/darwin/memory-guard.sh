#!/usr/bin/env bash
# memory-guard — end a runaway batch job before macOS starts pausing apps.
#
# WHY (Oops 2026-09-15 10:28): a `diarize` python (4.3 GB, 443 % CPU) ran with
# the SSD 99 % full. The kernel could not grow swap (`vnode_setsize for swap
# files failed: 28`, `low swap: failed to create swapfile`), declared swap
# exhaustion and SUSPENDED GUI apps (Claude, Beeper, kitty), the Force Quit
# "out of application memory" dialog. macOS picks the victims itself, and a
# user process cannot change jetsam priorities (memorystatus_control needs root
# plus an entitlement), so the only user-level lever is to free the memory
# FIRST, by killing the biggest non-app process.
#
# Trigger (checked every 10 s by launchd; cheap sysctls only):
#   * kern.memorystatus_vm_pressure_level == 4 (critical), or
#   * swap is nearly exhausted: < 1 GiB swap free AND < 3 GiB free on the VM
#     volume, the state in which the kernel starts suspending apps.
# Victim: the largest process of this user by physical footprint (top's MEM,
# which includes compressed pages) that is at least MIN_MB and is NOT an app
# in /Applications or ~/Applications, a system binary, or on the protected list
# below. Apps (Dayflow, Dia, Beeper, kitty, Wispr Flow, Claude.app) are never
# touched.
set -uo pipefail

MIN_MB=1500
LOG_TAG="memory-guard"
# Never killed even though they are not .app bundles.
PROTECTED_RE='(/claude$|/kitty$|/tmux$|/zsh$|/bash$|/nvim$|/Hammerspoon|/sketchybar|/aerospace|/borders$|/syncthing$|/nix-daemon$)'

pressure="$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)"
# "total = 9216.00M  used = 7609.00M  free = 1607.00M  (encrypted)"
swap_free_mb="$(sysctl -n vm.swapusage | sed -E 's/.*free = ([0-9.]+)M.*/\1/' | cut -d. -f1)"
vm_free_mb="$(/bin/df -k -P /System/Volumes/VM | tail -1 | awk '{printf "%d", $4/1024}')"

reason=""
if [ "$pressure" = "4" ]; then
  reason="memory pressure critical"
elif [ "${swap_free_mb:-99999}" -lt 1024 ] && [ "${vm_free_mb:-99999}" -lt 3072 ]; then
  reason="swap nearly exhausted (${swap_free_mb} MB swap free, ${vm_free_mb} MB disk free)"
fi
[ -z "$reason" ] && exit 0

# top -l 1: one sample; MEM column is the physical footprint ("4349M", "812K", "3G").
victim_pid=""
victim_mb=0
victim_cmd=""
while read -r pid mem; do
  case "$mem" in
    *G*) mb=$(echo "${mem%%[G+-]*}" | awk '{printf "%d", $1*1024}') ;;
    *M*) mb=$(echo "${mem%%[M+-]*}" | awk '{printf "%d", $1}') ;;
    *) continue ;;
  esac
  [ "$mb" -lt "$MIN_MB" ] && break # sorted by mem: nothing bigger follows
  owner="$(ps -o user= -p "$pid" 2>/dev/null | tr -d ' ')"
  [ "$owner" = "$(id -un)" ] || continue
  cmd="$(ps -o comm= -p "$pid" 2>/dev/null)"
  case "$cmd" in
    # Installed apps and the OS. Not a blanket *.app/* : the CLT python3 runs
    # as /Library/Developer/.../Python.app/Contents/MacOS/Python.
    '' | /Applications/* | "$HOME"/Applications/* | /System/* | /usr/libexec/* | /usr/sbin/*) continue ;;
  esac
  printf '%s\n' "$cmd" | grep -Eq "$PROTECTED_RE" && continue
  victim_pid="$pid"
  victim_mb="$mb"
  victim_cmd="$cmd"
  break
done < <(top -l 1 -o mem -n 25 -stats pid,mem 2>/dev/null | awk '/^PID/{f=1;next} f && NF==2')

stamp="$(date -Iseconds)"
if [ -z "$victim_pid" ]; then
  echo "$stamp $reason; no batch process >= ${MIN_MB} MB to end (apps are left to macOS)"
  exit 0
fi

args="$(ps -o args= -p "$victim_pid" 2>/dev/null | cut -c1-200)"
echo "$stamp $reason; ending pid $victim_pid (${victim_mb} MB): $args"
kill -TERM "$victim_pid" 2>/dev/null
for _ in 1 2 3 4 5; do
  sleep 1
  kill -0 "$victim_pid" 2>/dev/null || break
done
kill -0 "$victim_pid" 2>/dev/null && kill -KILL "$victim_pid" 2>/dev/null && echo "$stamp pid $victim_pid ignored TERM; sent KILL"

name="${victim_cmd##*/}"
/usr/bin/osascript -e "display notification \"Ended ${name} (pid ${victim_pid}, ${victim_mb} MB) so apps would not be paused. Log: ~/.local/state/memory-guard.log\" with title \"Memory guard: ${reason%% (*}\"" >/dev/null 2>&1 || true
logger -t "$LOG_TAG" "ended pid $victim_pid ($victim_mb MB) $name: $reason"
