#!/usr/bin/env bash
HISTORY_FILE="$HOME/.hypr_workspace_history"
MAX_HISTORY=10

# Ensure the history file exists
touch "$HISTORY_FILE"

# Function to update workspace history
update_history() {
    local current_workspace=$(hyprctl activeworkspace -j | jq -r '.id')
    if [[ -z "$current_workspace" || "$current_workspace" == "null" ]]; then
        return
    fi

    # Read current history
    mapfile -t history < <(cat "$HISTORY_FILE" 2>/dev/null)

    # Remove duplicates and limit history size
    history=("$current_workspace" "${history[@]}")
    history=($(printf "%s\n" "${history[@]}" | awk '!seen[$0]++' | head -n "$MAX_HISTORY"))

    # Save updated history
    printf "%s\n" "${history[@]}" > "$HISTORY_FILE"
}

# Continuously monitor workspace changes
socat -u "UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" - | while read -r line; do
    if [[ "$line" == "*>>workspace*" ]]; then
        update_history 
    fi
done
