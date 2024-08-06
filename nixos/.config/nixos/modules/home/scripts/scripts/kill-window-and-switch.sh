#!/usr/bin/env bash

# Count the number of windows in the current workspace
window_count=$(hyprctl activeworkspace -j | jq -r .windows)

# Boolean variable to check if there is only one window
only_one_window=false

# Check if there's only one window
if [ "$window_count" -eq 1 ]; then
    only_one_window=true
fi

# Kill the active window
hyprctl dispatch killactive ""

# If there was only one window, move to the previous workspace
if [ "$only_one_window" = true ]; then
    hyprctl dispatch workspace e-2
    hyprctl dispatch workspace e-1
fi

