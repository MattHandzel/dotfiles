#!/usr/bin/env bash

# File to track the state of focus mode
FOCUS_MODE_FILE="/tmp/focus_mode"
STATUS_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/focus-mode-waybar-status.json"

toggle_focus_mode() {
  if [[ -f "$FOCUS_MODE_FILE" ]]; then
    rm "$FOCUS_MODE_FILE"
    notify-send -t 2000 -u normal -i dialog-information "Focus Mode Off" "You can now access all applications."
    update_waybar_status "off"
    hyprctl keyword general:col.active_border "rgb(cba6f7) rgb(94e2d5) 45deg"
  else
    touch "$FOCUS_MODE_FILE"
    notify-send -t 2000 -u critical -i dialog-warning "Focus Mode On" "Stay focused! Distracting apps will have a 10s delay."
    update_waybar_status "on"
    hyprctl keyword general:col.active_border "rgb(fab387) rgb(f38ba8) 45deg"
  fi
}

update_waybar_status() {
  local status="$1"
  if [[ "$status" == "on" ]]; then
    printf '{"text":"󱫠","class":["on"],"tooltip":"Focus Mode: ON (Distracting apps delayed)"}\n' > "$STATUS_FILE"
  else
    printf '{"text":"󱫪","class":["off"],"tooltip":"Focus Mode: OFF"}\n' > "$STATUS_FILE"
  fi
  # Signal waybar to refresh if needed (optional since waybar can poll)
  # pkill -RTMIN+8 waybar
}

# Initialize status file if it doesn't exist or on call
if [[ "$1" == "--status" ]]; then
  if [[ -f "$FOCUS_MODE_FILE" ]]; then
    update_waybar_status "on"
  else
    update_waybar_status "off"
  fi
  cat "$STATUS_FILE"
else
  toggle_focus_mode
fi
