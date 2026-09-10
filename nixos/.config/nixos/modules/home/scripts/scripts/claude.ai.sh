#!/usr/bin/env bash

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="https://claude.ai" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland "$@"
