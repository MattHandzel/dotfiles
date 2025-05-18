#!/usr/bin/env bash
HISTORY_FILE="$HOME/.config/hypr/.hypr_workspace_history"
MAX_HISTORY=10

touch "$HISTORY_FILE"
tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"

hyprctl -j events | jq -r 'select(.event == "workspace") | .workspace' | while read -r ws; do
    history=($(cat "$HISTORY_FILE"))
    [[ "${history[-1]}" != "$ws" ]] && echo "$ws" >> "$HISTORY_FILE"
    tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
done
