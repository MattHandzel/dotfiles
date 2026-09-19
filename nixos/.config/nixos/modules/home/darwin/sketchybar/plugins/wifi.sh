#!/usr/bin/env bash
# Wi-Fi: SSID when joined; a struck-out glyph when off or unjoined.
# `networksetup -getairportnetwork` stopped returning the SSID in 14.4;
# `ipconfig getsummary` still does. Wired (Thunderbolt/Ethernet) shows a plug.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"

iface="$(/usr/sbin/networksetup -listallhardwareports 2>/dev/null | /usr/bin/awk '/Wi-Fi/{getline; print $2; exit}')"
iface="${iface:-en0}"
ssid="$(/usr/sbin/ipconfig getsummary "$iface" 2>/dev/null | /usr/bin/awk -F': ' '/^ *SSID/{print $2; exit}')"
# macOS 26 hands out "<redacted>" instead of the SSID to any process that
# lacks Location Services — even as root. Treat that as "joined, name
# unknown" rather than printing the placeholder on the bar. Grant
# Location Services to sketchybar and the real name comes back.
case "$ssid" in "<redacted>"|"<redacted>"*) ssid="" ; joined=1 ;; *) joined=0 ;; esac
power="$(/usr/sbin/networksetup -getairportpower "$iface" 2>/dev/null | /usr/bin/awk '{print $NF}')"

if [ -n "$ssid" ]; then
  /opt/homebrew/bin/sketchybar --set "$NAME" icon="󰤨" icon.color="$BLUE" label="$ssid" label.drawing=on
elif [ "$joined" = "1" ]; then
  # Joined, but macOS will not tell us the name yet.
  /opt/homebrew/bin/sketchybar --set "$NAME" icon="󰤨" icon.color="$BLUE" label.drawing=off
elif /sbin/route -n get default 2>/dev/null | /usr/bin/grep -q 'interface:'; then
  # Online without Wi-Fi: wired.
  /opt/homebrew/bin/sketchybar --set "$NAME" icon="󰈀" icon.color="$BLUE" label.drawing=off
elif [ "$power" = "Off" ]; then
  /opt/homebrew/bin/sketchybar --set "$NAME" icon="󰤮" icon.color="$OVERLAY1" label.drawing=off
else
  /opt/homebrew/bin/sketchybar --set "$NAME" icon="󰤯" icon.color="$OVERLAY1" label.drawing=off
fi
