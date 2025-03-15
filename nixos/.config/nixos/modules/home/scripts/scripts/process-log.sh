#!/usr/bin/env bash
# Usage: ./ps_logger.sh <interval_in_seconds>

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <interval_in_seconds>"
    exit 1
fi

INTERVAL="$1"
OUTPUT_DIR="$HOME/notes/life-logging/process-logging"
mkdir -p "$OUTPUT_DIR"

# Function to capture the output of 'ps aux'
log_ps_aux() {
    CURRENT_TIME=$(date +'%Y-%m-%d_%H-%M-%S.%3N %Z')
    FILENAME="${CURRENT_TIME}_ps_aux.log"
    FILEPATH="${OUTPUT_DIR}/${FILENAME}"
    ps aux > "$FILEPATH"
}

# Main loop: log process list every INTERVAL seconds
while true; do
    log_ps_aux
    sleep "$INTERVAL"
done
