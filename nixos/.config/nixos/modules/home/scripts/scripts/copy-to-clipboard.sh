#!/usr/bin/env bash
# Check if there's input from a pipe
if [ -p /dev/stdin ]; then
    # Read from stdin if piped
    input=$(cat)
else
    # If no piped input, use wl-paste
    input=$(wl-paste)
fi

# Copy the content to the clipboard

# Store the content in cliphist
echo -n "$input" | cliphist store
echo -n "$input" | wl-copy

echo "Content copied to clipboard and stored in history."
