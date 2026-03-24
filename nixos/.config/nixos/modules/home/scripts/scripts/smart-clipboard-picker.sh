#!/usr/bin/env bash

# Picker for various quick copy actions
CHOICE=$(echo -e "Links from Clipboard\nLinks from Obsidian Vault\nImages from Clipboard\nClear Clipboard" | fuzzel -d -w 50 -p "Copy > ")

if [ -z "$CHOICE" ]; then
    exit 0
fi

case "$CHOICE" in
    "Links from Clipboard")
        # Get clipboard items, grep for URLs, and present them in fuzzel
        SELECTED_LINK=$(cliphist list | grep -E 'https?://' | fuzzel -d -w 100 -p "Clipboard Links > ")
        if [ -n "$SELECTED_LINK" ]; then
            echo "$SELECTED_LINK" | cliphist decode | wl-copy
            notify-send "Copied Link" "Link copied to clipboard."
        fi
        ;;
    "Links from Obsidian Vault")
        # Search the Obsidian vault for URLs
        OBSIDIAN_DIR="$HOME/Obsidian"
        
        if [ -d "$OBSIDIAN_DIR" ]; then
            # Using rg (ripgrep) to find all URLs in markdown files, sorted and unique
            SELECTED_LINK=$(rg -hoE 'https?://[^" )>]+' "$OBSIDIAN_DIR" | sort -u | fuzzel -d -w 100 -p "Obsidian Links > ")
            if [ -n "$SELECTED_LINK" ]; then
                echo -n "$SELECTED_LINK" | wl-copy
                notify-send "Copied Link" "Obsidian link copied to clipboard."
            fi
        else
            notify-send "Error" "Obsidian directory not found at $OBSIDIAN_DIR"
            exit 1
        fi
        ;;
    "Images from Clipboard")
        SELECTED_IMAGE=$(cliphist list | grep -E '\[\[ binary data' | fuzzel -d -w 100 -p "Images > ")
        if [ -n "$SELECTED_IMAGE" ]; then
            echo "$SELECTED_IMAGE" | cliphist decode | wl-copy
            notify-send "Copied Image" "An image was copied to your clipboard."
        fi
        ;;
    "Clear Clipboard")
        cliphist wipe
        notify-send "Clipboard Cleared" "All clipboard history has been wiped."
        ;;
esac