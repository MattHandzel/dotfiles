#!/usr/bin/env bash

exec chromium --app="https://gemini.google.com" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland "$@"
