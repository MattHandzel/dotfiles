#!/usr/bin/env bash
HISTORY_FILE="$HOME/.hypr_window_history"
current_window=$(hyprctl -j activewindow | jq -r '.address')

mapfile -t history < <(tac "$HISTORY_FILE" 2>/dev/null)
current_index=-1

for i in "${!history[@]}"; do
    [[ "${history[i]}" == "$current_window" ]] && current_index=$i && break
done

if (( current_index == -1 )); then
    hyprctl dispatch cyclenext prev
else
    next_index=$(( (current_index + 1) % ${#history[@]} ))
    next_window="${history[next_index]}"
    hyprctl dispatch focuswindow "address:$next_window"
fi
