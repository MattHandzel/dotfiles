#!/usr/bin/env bash

# Get the website name from the URL
app=$1

name=$(echo "$app" | awk -F[/:] '{print $4}' | sed 's/www.//;s/\..*//')

echo "$name"

# macOS: the same site as a standalone Chrome app window (Chrome keeps the
# separate chromium-app profile, like the Linux --user-data-dir).
if [[ "$(uname)" == Darwin ]]; then
  exec open -na "Google Chrome" --args --app="$app" --user-data-dir="$HOME/.config/chromium-app"
fi


exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app=$app --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland "$@"
