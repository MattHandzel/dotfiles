#!/bin/bash

# Define the notes directory
NOTES_DIR="$HOME/notes/capture/raw_capture"

# Get the current date in the format YYYY-MM-DD
TODAY=$(date +%Y-%m-%d)

# Get the current timestamp in the format YYYY-MM-DD HH:MM
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")

# Define the file for today's notes
TODAY_FILE="${NOTES_DIR}/${TODAY}.md"

# Initialize variables for text and clipboard content
TEXT=""
CLIPBOARD_CONTENT=""

# Parse the arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--clipboard)
            CLIPBOARD_CONTENT=$(wl-paste)
            shift
            ;;
        *)
            TEXT="$*"
            break
            ;;
    esac
done

# Ensure that either text or clipboard content is provided
if [ -z "$TEXT" ] && [ -z "$CLIPBOARD_CONTENT" ]; then
    echo "No note provided. Please provide a note as an argument or use -c to take from clipboard."
    exit 1
fi

# Format the note
NOTE="${TIMESTAMP}\n"
if [ -n "$TEXT" ]; then
    NOTE+="Text: \"$TEXT\"\n"
fi
if [ -n "$CLIPBOARD_CONTENT" ]; then
    NOTE+="Clipboard: \n\"\"\"\n$CLIPBOARD_CONTENT\"\"\"\n"
fi

# Append the note to today's file
echo -e "$NOTE" >> "${TODAY_FILE}"

# Confirmation message
echo "Note added to ${TODAY_FILE}"
