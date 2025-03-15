#!/usr/bin/env bash
# Usage: ./screen_logger.sh <interval_in_seconds>

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <interval_in_seconds>"
    exit 1
fi

INTERVAL="$1"
OUTPUT_DIR="$HOME/notes/life-logging/screen-logging"
mkdir -p "$OUTPUT_DIR"

# Function to capture a screenshot for every monitor
capture_picture() {
    CURRENT_TIME=$(date +'%Y-%m-%d_%H-%M-%S.%3N %Z')
    # Get a list of monitor names using hyprctl
    # monitors=$(hyprctl monitors | sed -n 's/^[[:space:]]*[0-9]\+:[[:space:]]*\([^:]\+\):.*/\1/p')
    
    FILENAME="${CURRENT_TIME}_${monitor}.png"
    FILEPATH="${OUTPUT_DIR}/${FILENAME}"
    grim "$FILEPATH"
    # for monitor in $monitors; do
    #     grim -o "$monitor" "$FILEPATH"
    #     echo "Saved screenshot for monitor '$monitor' as $FILEPATH"
    # done
}

# Main loop: take a screenshot every INTERVAL seconds
while true; do
    capture_picture
    sleep "$INTERVAL"
done
