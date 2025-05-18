#!/usr/bin/env bash
HISTORY_FILE="$HOME/.hypr_workspace_history"
current_ws=$(hyprctl -j activeworkspace | jq -r '.id')

mapfile -t history < <(tac "$HISTORY_FILE" 2>/dev/null)
current_index=-1

for i in "${!history[@]}"; do
    [[ "${history[i]}" == "$current_ws" ]] && current_index=$i && break
done

if (( current_index == -1 )); then
    hyprctl dispatch workspace previous
else
    next_index=$(( (current_index + 1) % ${#history[@]} ))
    next_ws="${history[next_index]}"
    hyprctl dispatch workspace "$next_ws"
fi
