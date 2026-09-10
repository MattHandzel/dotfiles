#!/usr/bin/env bash

# macOS: the same site as a standalone Chrome app window (Chrome keeps the
# separate chromium-app profile, like the Linux --user-data-dir).
if [[ "$(uname)" == Darwin ]]; then
  exec open -na "Google Chrome" --args --app="https://gemini.google.com" --user-data-dir="$HOME/.config/chromium-app"
fi

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="https://gemini.google.com" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland "$@"
