#!/usr/bin/env bash
# Tailscale: green dot when the tailnet is up, red when it is not, dim grey
# when the CLI is missing. Hover-free — it is a dot on purpose.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"

TS=""
for c in /run/current-system/sw/bin/tailscale /opt/homebrew/bin/tailscale \
         "/Applications/Tailscale.app/Contents/MacOS/Tailscale"; do
  [ -x "$c" ] && { TS="$c"; break; }
done

if [ -z "$TS" ]; then
  /opt/homebrew/bin/sketchybar --set "$NAME" icon.color="$OVERLAY0"
  exit 0
fi

state="$($TS status --json 2>/dev/null | /opt/homebrew/bin/jq -r '.BackendState // empty' 2>/dev/null)"
if [ "$state" = "Running" ]; then
  /opt/homebrew/bin/sketchybar --set "$NAME" icon.color="$GREEN"
else
  /opt/homebrew/bin/sketchybar --set "$NAME" icon.color="$RED"
fi
