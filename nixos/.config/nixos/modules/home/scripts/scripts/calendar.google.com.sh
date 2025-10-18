#!/usr/bin/env bash

exec chromium --app="https://calendar.google.com/calendar/u/0/r" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland "$@"
