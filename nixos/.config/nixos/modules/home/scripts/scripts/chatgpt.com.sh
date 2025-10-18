#!/usr/bin/env bash

exec chromium --app="https://chatgpt.com" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland "$@"
