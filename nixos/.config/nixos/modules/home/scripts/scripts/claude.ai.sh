#!/usr/bin/env bash

exec chromium --app="https://claude.ai" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland "$@"
