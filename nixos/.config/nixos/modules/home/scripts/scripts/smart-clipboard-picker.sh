#!/usr/bin/env bash

# Picker for various quick copy actions.
# Linux: clipboard history comes from cliphist. macOS: Raycast owns clipboard
# history (⌥V), which has no CLI, so the history entries hand off to Raycast and
# the vault-links + clear entries work natively.
if [[ "$(uname)" == Darwin ]]; then
    pick() { choose -n 12 -w "${2:-50}" -p "$1"; }
    copy() { pbcopy; }
    MENU="Links from Obsidian Vault\nLinks from Clipboard (Raycast ⌥V)\nImages from Clipboard (Raycast ⌥V)\nClear Clipboard"
else
    pick() { fuzzel -d -w "${2:-50}" -p "$1"; }
    copy() { wl-copy; }
    MENU="Links from Clipboard\nLinks from Obsidian Vault\nImages from Clipboard\nClear Clipboard"
fi

CHOICE=$(echo -e "$MENU" | pick "Copy > ")

if [ -z "$CHOICE" ]; then
    exit 0
fi

case "$CHOICE" in
    "Links from Clipboard")
        # Get clipboard items, grep for URLs, and present them in fuzzel
        SELECTED_LINK=$(cliphist list | grep -E 'https?://' | pick "Clipboard Links > " 100)
        if [ -n "$SELECTED_LINK" ]; then
            echo "$SELECTED_LINK" | cliphist decode | copy
            notify-send "Copied Link" "Link copied to clipboard."
        fi
        ;;
    "Links from Clipboard (Raycast ⌥V)" | "Images from Clipboard (Raycast ⌥V)")
        open "raycast://extensions/raycast/clipboard-history/clipboard-history"
        ;;
    "Links from Obsidian Vault")
        # Search the Obsidian vault for URLs
        OBSIDIAN_DIR="$HOME/Obsidian"

        if [ -d "$OBSIDIAN_DIR" ]; then
            # Using rg (ripgrep) to find all URLs in markdown files, sorted and unique
            SELECTED_LINK=$(rg -hoE 'https?://[^" )>]+' "$OBSIDIAN_DIR" | sort -u | pick "Obsidian Links > " 100)
            if [ -n "$SELECTED_LINK" ]; then
                echo -n "$SELECTED_LINK" | copy
                notify-send "Copied Link" "Obsidian link copied to clipboard."
            fi
        else
            notify-send "Error" "Obsidian directory not found at $OBSIDIAN_DIR"
            exit 1
        fi
        ;;
    "Images from Clipboard")
        SELECTED_IMAGE=$(cliphist list | grep -E '\[\[ binary data' | pick "Images > " 100)
        if [ -n "$SELECTED_IMAGE" ]; then
            echo "$SELECTED_IMAGE" | cliphist decode | copy
            notify-send "Copied Image" "An image was copied to your clipboard."
        fi
        ;;
    "Clear Clipboard")
        if [[ "$(uname)" == Darwin ]]; then
            pbcopy </dev/null
            notify-send "Clipboard Cleared" "Clipboard emptied (Raycast history: ⌥V → ⌘⇧⌫ to clear)."
        else
            cliphist wipe
            notify-send "Clipboard Cleared" "All clipboard history has been wiped."
        fi
        ;;
esac
