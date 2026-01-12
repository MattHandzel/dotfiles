#!/usr/bin/env bash
set -euo pipefail

# Directory containing prompt markdown files
PROMPTS_DIR="$HOME/Obsidian/Main/resources/prompts"

if [ ! -d "$PROMPTS_DIR" ]; then
    notify-send -u critical "Prompt Picker" "Directory not found: $PROMPTS_DIR"
    exit 1
fi

# List files, strip extension for cleaner display, sort
# We use find to get filenames, then sed to strip path and extension
SELECTED_NAME=$(find "$PROMPTS_DIR" -maxdepth 1 -name "*.md" -printf "%f\n" | \
    sed 's/\.md$//' | \
    sort | \
    fuzzel --dmenu --prompt="Prompts > " --lines=15 --width=60)

if [ -z "$SELECTED_NAME" ]; then
    exit 0
fi

FULL_PATH="$PROMPTS_DIR/${SELECTED_NAME}.md"

if [ ! -f "$FULL_PATH" ]; then
    notify-send -u error "Prompt Picker" "File not found: $FULL_PATH"
    exit 1
fi

# Read content, stripping frontmatter if present
CONTENT=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{f=0;next} !f' "$FULL_PATH")

# Copy to clipboard
echo -n "$CONTENT" | wl-copy

# Notify
notify-send -u low "Prompt Picker" "Copied: $SELECTED_NAME"

# Paste logic: press Ctrl+V
# We use wtype to simulate keypresses
if command -v wtype >/dev/null 2>&1; then
    # wtype -M ctrl -k v -m ctrl
    # Using the sequence from your existing config for reliability
    wtype -M ctrl "v"
    sleep 0.05
    wtype -m ctrl
else
    notify-send -u error "Prompt Picker" "wtype not found, cannot auto-paste"
fi
