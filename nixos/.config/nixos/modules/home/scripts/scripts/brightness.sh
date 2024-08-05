#!/usr/bin/env bash

main_monitor_brightnesses=(0.0 0.0275 0.12 0.20 0.30 0.37)
external_monitor_brightnesses=(0.13 0.20 0.40 0.60 0.80 1.00)
max_brightness_for_external_monitor=100

# Function to interpolate
interpolate() {
    local val=$1
    local xs=("${!2}")
    local ys=("${!3}")

    if (( $(echo "$val < ${xs[0]}" | bc -l) )); then
        echo "${ys[0]}"
        return
    fi

    if (( $(echo "$val > ${xs[-1]}" | bc -l) )); then
        echo "${ys[-1]}"
        return
    fi

    for (( i=0; i<${#xs[@]}-1; i++ )); do
        if (( $(echo "$val >= ${xs[$i]} && $val <= ${xs[$((i+1))]}" | bc -l) )); then
            left=$i
            right=$((i+1))
            break
        fi
    done

    left_x=${xs[$left]}
    right_x=${xs[$right]}
    left_y=${ys[$left]}
    right_y=${ys[$right]}

    echo "$(echo "$left_y + ($val - $left_x) * ($right_y - $left_y) / ($right_x - $left_x)" | bc -l)"
}

# Parse arguments
while getopts "s:i:d:" opt; do
  case ${opt} in
    s ) set_level=$OPTARG ;;
    i ) increase_amount=$OPTARG ;;
    d ) decrease_amount=$OPTARG ;;
    \? ) echo "Usage: cmd [-s] [-i] [-d]"
         exit 1 ;;
  esac
done

increase_amount=${increase_amount:-0}
decrease_amount=${decrease_amount:-0}

# Get current brightness
current_brightness=$(brightnessctl get)
max_brightness=$(brightnessctl max)
brightness_as_a_percentage=$(echo "$current_brightness / $max_brightness * 100" | bc -l)

# Calculate new brightness level
if [[ -z "$set_level" ]]; then
    new_brightness=$(echo "$brightness_as_a_percentage + $increase_amount - $decrease_amount" | bc -l)
else
    new_brightness=$set_level
fi

new_brightness=$(echo "scale=4; $new_brightness / 100" | bc -l)
new_brightness=$(echo "if ($new_brightness < 0) 0 else if ($new_brightness > 1) 1 else $new_brightness" | bc -l)

main_monitor_brightness=$(printf "%.0f" $(echo "$new_brightness * $max_brightness" | bc -l))
external_monitor_brightness=$(printf "%.0f" $(echo "$(interpolate $new_brightness main_monitor_brightnesses[@] external_monitor_brightnesses[@]) * $max_brightness_for_external_monitor" | bc -l))

# Set brightness
brightnessctl set "${main_monitor_brightness}" > /dev/null


# This will make it so that the secondary monitor will update its brightness level after a second of waiting
LOCKFILE="/tmp/external_monitor_brightness_update.lock"

# Function to clean up the lock file on exit
cleanup() {
    rm -f "$LOCKFILE"
}

# Set the trap to clean up the lock file when the script exits
trap cleanup EXIT

# Check if the lock file exists and a process is running
if [[ -f "$LOCKFILE" ]]; then
    # Kill the process stored in the lock file
    kill -9 "$(cat "$LOCKFILE")" 2>/dev/null
fi

# Store the current process ID in the lock file
echo $$ > "$LOCKFILE"

# Wait for 1 second
sleep 1

ddcutil setvcp 10 "${external_monitor_brightness}"
