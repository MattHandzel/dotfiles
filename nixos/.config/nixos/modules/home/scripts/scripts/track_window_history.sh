#!/usr/bin/env bash
HISTORY_FILE="$HOME/.config/hypr/.hypr_window_history"
MAX_HISTORY=25

touch "$HISTORY_FILE"
tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"

hyprctl -j events | jq -r 'select(.event == "activewindow") | .window' | while read -r window; do
    history=($(cat "$HISTORY_FILE"))
    [[ "${history[-1]}" != "$window" ]] && echo "$window" >> "$HISTORY_FILE"
    tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "$HISTORY_FILE.tmp" && mv "$HISTORY_FILE.tmp" "$HISTORY_FILE"
done
