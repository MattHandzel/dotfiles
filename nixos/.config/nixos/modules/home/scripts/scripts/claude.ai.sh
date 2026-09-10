#!/usr/bin/env bash

# macOS: prefer the native Claude app when it is installed; otherwise the
# same site as a standalone Chrome app window.
if [[ "$(uname)" == Darwin ]]; then
  [ -d "/Applications/Claude.app" ] && exec open -a "Claude"
  exec open -na "Google Chrome" --args --app="https://claude.ai" --user-data-dir="$HOME/.config/chromium-app"
fi

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="https://claude.ai" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland "$@"
