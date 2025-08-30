#!/usr/bin/env bash

exec chromium --app="https://app.reclaim.ai/planner?taskSort=schedule" --user-data-dir="$HOME/.config/reclaim-app" --ozone-platform=wayland "$@"
