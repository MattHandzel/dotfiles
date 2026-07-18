#!/usr/bin/env bash
# ntfy-gui — open the ntfy web UI as a standalone desktop app window. The server
# at server.matthandzel.com:8124 serves the full ntfy web app, so this is a real
# GUI client for browsing topics/messages (same chromium --app pattern as the
# calendar / claude.ai launchers).
exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="http://server.matthandzel.com:8124/" \
  --user-data-dir="$HOME/.config/chromium-app" \
  --class="ntfy" \
  --ozone-platform=wayland "$@"
