#! /usr/bin/env bash
# Notion Calendar as a desktop app.
#
# Notion ships no Linux client ("We don't have a Linux app at the moment"), so the
# web app is the only route. Same wrapper technique as calendar.sh, and the same
# chromium profile so the Google session is shared with the Google Calendar app.

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="https://calendar.notion.so" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland --force-device-scale-factor=1.25 "$@"
