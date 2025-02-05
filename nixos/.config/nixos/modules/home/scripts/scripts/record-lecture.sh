#!/bin/bash

# Configuration - Add your courses here
declare -A courses=(
    # Format: ["COURSE"]="TIMEOUT:DESTINATION_DIRECTORY"
    ["CS510"]="90m:$HOME/notes/projects/uiuc/CS510"
    ["CS461"]="90m:$HOME/notes/projects/uiuc/CS461"
    ["CS442"]="90m:$HOME/notes/projects/uiuc/CS442"

    # Add new courses in format: ["COURSE"]="TIMEOUT:PATH"
)

# Print help menu
function show_help() {
    echo "Usage: ${0##*/} COURSE_CODE LECTURE_TITLE..."
    echo "Options:"
    echo "  --dry-run    Test the command without recording"
    echo "  --help       Show this help menu"
    echo ""
    echo "Available courses:"
    for course in "${!courses[@]}"; do
        IFS=':' read -r timeout path <<< "${courses[$course]}"
        echo "  $course: Timeout=$timeout, Path=$path"
    done
    exit 0
}

# Validate arguments
if [[ $# -lt 2 || "$1" == "--help" ]]; then
    show_help
fi

# Check for dry-run mode
dry_run=false
if [[ "$1" == "--dry-run" ]]; then
    dry_run=true
    shift
fi

# Parse course and lecture title
course="$1"
shift
lecture_title="$*"

# Check if course exists in configuration
if [[ ! -v courses[$course] ]]; then
    echo "Error: Course '$course' not configured."
    echo "Available courses: ${!courses[@]}"
    exit 1
fi

# Extract timeout and destination directory
IFS=':' read -r timeout destination_dir <<< "${courses[$course]}"

# Sanitize lecture title for filename
sanitized_title=$(echo "$lecture_title" | tr -cd '[:alnum:]._-' | tr ' ' '_')
output_path="$destination_dir/$sanitized_title.wav"

# Create directory if needed
mkdir -p "$destination_dir"

# Logging
function log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Dry-run mode
if $dry_run; then
    log "Dry-run mode enabled. No recording will be made."
    log "Course: $course"
    log "Timeout: $timeout"
    log "Lecture Title: $lecture_title"
    log "Output Path: $output_path"
    exit 0
fi

# Start recording
log "Starting recording for course '$course'..."
log "Lecture Title: $lecture_title"
log "Timeout: $timeout"
log "Output Path: $output_path"

timeout "$timeout" arecord -f cd "$output_path"

# Check if recording was successful
if [[ $? -eq 0 ]]; then
    log "Recording completed successfully."
else
    log "Recording stopped (timeout or error)."
fi
