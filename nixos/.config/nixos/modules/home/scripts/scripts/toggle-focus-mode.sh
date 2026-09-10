#!/usr/bin/env bash
# Focus Mode flag controller. The flag is a file (/tmp/focus_mode) that the
# enforcer service, focus_app, and waybar all read.
#
#   toggle-focus-mode            # flip
#   toggle-focus-mode on|off     # set explicitly (idempotent) — used by the
#                                #   calendar sync service (focus-mode-sync)
#   toggle-focus-mode --status   # print the waybar JSON for the current state

FOCUS_MODE_FILE="/tmp/focus_mode"
STATUS_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/focus-mode-waybar-status.json"

write_status() {
  if [[ "$1" == "on" ]]; then
    printf '{"text":"󱫠","class":["on"],"tooltip":"Focus Mode: ON (Distracting apps delayed)"}\n' >"$STATUS_FILE"
  else
    printf '{"text":"󱫪","class":["off"],"tooltip":"Focus Mode: OFF"}\n' >"$STATUS_FILE"
  fi
}

turn_on() {
  touch "$FOCUS_MODE_FILE"
  notify-send -t 2000 -u normal -i dialog-warning "Focus Mode On" "Stay focused! Distracting apps will have a 10s delay."
  write_status on
  hyprctl keyword general:col.active_border "rgb(fab387) rgb(f38ba8) 45deg" >/dev/null 2>&1
}

turn_off() {
  rm -f "$FOCUS_MODE_FILE"
  notify-send -t 2000 -u normal -i dialog-information "Focus Mode Off" "You can now access all applications."
  write_status off
  hyprctl keyword general:col.active_border "rgb(cba6f7) rgb(94e2d5) 45deg" >/dev/null 2>&1
}

case "${1:-toggle}" in
  --status)
    [[ -e "$FOCUS_MODE_FILE" ]] && write_status on || write_status off
    cat "$STATUS_FILE"
    ;;
  on) [[ -e "$FOCUS_MODE_FILE" ]] || turn_on ;;
  off) [[ -e "$FOCUS_MODE_FILE" ]] && turn_off || true ;;
  toggle | "") [[ -e "$FOCUS_MODE_FILE" ]] && turn_off || turn_on ;;
  *)
    echo "usage: toggle-focus-mode [on|off|--status]" >&2
    exit 2
    ;;
esac
