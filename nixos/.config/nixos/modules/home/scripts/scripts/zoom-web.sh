#!/usr/bin/env bash
# zoom-web — Zoom web client as a standalone Chromium app window (same pattern
# as the linear/claude.ai launchers, shared chromium-app profile → one process,
# app-webapps slice). The native Linux client's Qt popups misbehave under
# Hyprland; the web client's menus are normal DOM and screen share goes
# through the PipeWire portal.
#
# Usage:
#   zoom-web                                       # web app home
#   zoom-web 123456789                             # join by meeting ID
#   zoom-web https://us02web.zoom.us/j/123?pwd=x   # native join link, rewritten
url="${1:-https://app.zoom.us/wc/home}"
if [[ "$url" =~ ^[0-9]{9,12}$ ]]; then
  url="https://app.zoom.us/wc/${url}/join"
elif [[ "$url" =~ zoom\.us/j/([0-9]+)(\?(.*))?$ ]]; then
  url="https://app.zoom.us/wc/${BASH_REMATCH[1]}/join${BASH_REMATCH[3]:+?${BASH_REMATCH[3]}}"
fi
# macOS: prefer the native zoom.us app when it is installed; otherwise the
# same site as a standalone Chrome app window.
if [[ "$(uname)" == Darwin ]]; then
  [ -d "/Applications/zoom.us.app" ] && exec open -a "zoom.us" "$url"
  exec open -na "Google Chrome" --args --app="$url" --user-data-dir="$HOME/.config/chromium-app"
fi

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="$url" \
  --user-data-dir="$HOME/.config/chromium-app" \
  --ozone-platform=wayland
