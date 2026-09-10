#! /usr/bin/env bash
# Otter.ai as a desktop app.
#
# Otter ships iOS/Android clients and a Chrome extension but no Linux build, so
# the web app is the route. Same wrapper technique as superhuman.sh, sharing the
# chromium-app profile so the Google session carries over.

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="https://otter.ai/home" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland --force-device-scale-factor=1.25 "$@"
