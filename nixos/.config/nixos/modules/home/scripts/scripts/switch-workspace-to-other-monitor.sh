#!/usr/bin/env

# Get the current monitor and workspace
current_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')
current_workspace=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .activeWorkspace.name')

# Determine the target monitor
if [ "$current_monitor" == "eDP-1" ]; then
    target_monitor="DP-1"
else
    target_monitor="eDP-1"
fi

# Move the workspace to the target monitor
hyprctl dispatch moveworkspacetomonitor "$current_workspace" "$target_monitor"

# Switch focus to the new location of the workspace
hyprctl dispatch focusmonitor "$target_monitor"
hyprctl dispatch workspace "$current_workspace"

