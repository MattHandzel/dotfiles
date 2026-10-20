#!/usr/bin/env bash
# lid-awake — keep the Mac running with the lid closed (pmset disablesleep).
#
#   lid-awake              toggle (awake with no timer <-> normal sleep)
#   lid-awake on [TIME]    stay awake; optional TIME = seconds, or 90s / 10m / 2h.
#                          When it runs out, normal sleep comes back and the Mac
#                          sleeps right away if the lid is shut.
#   lid-awake TIME         same as `on TIME`, e.g. `lid-awake 600`
#   lid-awake off          normal sleep again; cancels any timer
#   lid-awake status
#
# SleepDisabled survives a reboot but the timer doesn't — `status` warns.
#
# The timer is a throwaway LaunchAgent (same trick as leader-timer): Raycast
# reaps the process group of a script it ran, even through nohup/set -m, so a
# backgrounded countdown started from the Raycast command would die instantly.
# Needs passwordless `sudo pmset` (Matt's sudoers has NOPASSWD: ALL).

set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/lid-awake"
label_file="$state_dir/timer.label"
plist="$state_dir/timer.plist"
deadline_file="$state_dir/deadline"
log_file="$state_dir/log"
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
uid="$(id -u)"
# Use the system zone, not the caller's: after a flight Raycast still handed its
# scripts the zone it launched in, so "sleeps at" read an hour off (2026-10-19).
TZ="$(/usr/bin/readlink /etc/localtime | sed 's|.*/zoneinfo/||')" && export TZ
mkdir -p "$state_dir"

log() { echo "$(/bin/date '+%F %T') $*" >>"$log_file"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"lid-awake\"" >/dev/null 2>&1 || true; }
sleep_disabled() { [[ "$(/usr/bin/pmset -g | awk '/SleepDisabled/ {print $2}')" == 1 ]]; }
lid_closed() { /usr/sbin/ioreg -r -k AppleClamshellState -d 4 | grep -q '"AppleClamshellState" = Yes'; }
battery() { /usr/bin/pmset -g batt | grep -Eo '[0-9]+%' | head -1; }
clock() { /bin/date -r "$1" '+%H:%M:%S'; } # /bin/date: nix's GNU date reads -r as a file

human() {
  local s=$1
  if ((s >= 3600)); then printf '%dh %dm' $((s / 3600)) $((s % 3600 / 60))
  elif ((s >= 60)); then printf '%dm %ds' $((s / 60)) $((s % 60))
  else printf '%ds' "$s"; fi
}

to_seconds() {
  [[ "$1" =~ ^([0-9]+)([smh]?)$ ]] || return 1
  local n=${BASH_REMATCH[1]}
  case ${BASH_REMATCH[2]} in
    m) echo $((n * 60)) ;;
    h) echo $((n * 3600)) ;;
    *) echo "$n" ;;
  esac
}

timer_running() {
  [[ -f "$label_file" ]] && launchctl list "$(<"$label_file")" 2>/dev/null | grep -q '"PID"'
}

cancel_timer() {
  if [[ -f "$label_file" ]]; then
    launchctl bootout "gui/$uid/$(<"$label_file")" 2>/dev/null || true
  fi
  rm -f "$label_file" "$plist" "$deadline_file"
}

set_disablesleep() {
  if ! sudo -n /usr/bin/pmset -a disablesleep "$1" 2>/dev/null; then
    echo "lid-awake: 'sudo pmset' needs a password here; run: sudo pmset -a disablesleep $1" >&2
    exit 1
  fi
}

start_timer() {
  local deadline=$1
  # Unique label per timer, so a fresh bootstrap never races the bootout of the last one.
  local label="local.lid-awake.timer.$deadline.$$"
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>$self</string><string>__timer</string><string>$deadline</string>
  </array>
  <key>EnvironmentVariables</key><dict><key>HOME</key><string>$HOME</string></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$log_file</string>
  <key>StandardErrorPath</key><string>$log_file</string>
</dict></plist>
PLIST
  echo "$label" >"$label_file"
  echo "$deadline" >"$deadline_file"
  launchctl bootstrap "gui/$uid" "$plist"
}

cmd_on() {
  cancel_timer
  set_disablesleep 1
  if [[ -n "${1:-}" ]]; then
    local secs deadline
    secs=$(to_seconds "$1") || { echo "lid-awake: bad time '$1' (use 600, 90s, 10m, 2h)" >&2; exit 2; }
    deadline=$(($(/bin/date +%s) + secs))
    start_timer "$deadline"
    log "on for ${secs}s (until $(clock "$deadline"))"
    echo "Awake with lid closed for $(human "$secs") — sleeps at $(clock "$deadline"). Battery $(battery)."
  else
    log "on (no timer)"
    echo "Awake with lid closed, no timer. Run 'lid-awake off' to restore sleep. Battery $(battery)."
  fi
}

cmd_off() {
  cancel_timer
  set_disablesleep 0
  log "off"
  echo "Normal sleep restored — closing the lid sleeps the Mac."
}

cmd_timer() {
  local deadline=$1
  while (($(/bin/date +%s) < deadline)); do sleep 5; done
  set_disablesleep 0
  log "timer done, sleep restored"
  notify "Timer done — sleep restored"
  if lid_closed; then
    log "lid closed, sleeping now"
    /usr/bin/pmset sleepnow
  fi
  # Last: booting out our own job ends this process.
  cancel_timer
}

cmd_status() {
  if sleep_disabled; then
    echo "Lid-close sleep: OFF (Mac stays awake when closed). Battery $(battery)."
    if timer_running && [[ -f "$deadline_file" ]]; then
      local deadline left
      deadline=$(<"$deadline_file")
      left=$((deadline - $(/bin/date +%s)))
      ((left < 0)) && left=0
      echo "Timer: $(human "$left") left (sleeps at $(clock "$deadline"))."
    elif [[ -f "$deadline_file" ]]; then
      echo "WARNING: a timer was set but isn't running (reboot or killed?). Sleep stays off until 'lid-awake off'."
    else
      echo "No timer — stays awake until 'lid-awake off'."
    fi
  else
    echo "Lid-close sleep: ON (normal). Battery $(battery)."
  fi
}

case "${1:-toggle}" in
  toggle) if sleep_disabled; then cmd_off; else cmd_on; fi ;;
  on) cmd_on "${2:-}" ;;
  off) cmd_off ;;
  status) cmd_status ;;
  __timer) cmd_timer "$2" ;;
  -h | --help | help) sed -n '2,12p' "$self" | sed 's/^# \{0,1\}//' ;;
  *)
    if to_seconds "$1" >/dev/null; then cmd_on "$1"
    else echo "lid-awake: unknown command '$1' (try --help)" >&2; exit 2; fi
    ;;
esac
