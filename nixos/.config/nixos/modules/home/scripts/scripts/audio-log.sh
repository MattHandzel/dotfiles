#!/usr/bin/env bash

# Directory to save the audio file
echo "AUDIO LOG"

OUTPUT_DIR="/home/matth/notes/life-logging/audio-logging"
mkdir -p "$OUTPUT_DIR"

# Generate filename with the current date
FILENAME="$(date +"%Y-%m-%d_%H-%M-%S.%3N %Z").wav"
FILEPATH="$OUTPUT_DIR/$FILENAME"

# Start recording
echo "Recording started. Saving to $FILEPATH. Press Ctrl+C to stop."
arecord -D hw:1,0 -f cd "$FILEPATH" --nonblock
echo "Recording saved as $FILEPATH"
