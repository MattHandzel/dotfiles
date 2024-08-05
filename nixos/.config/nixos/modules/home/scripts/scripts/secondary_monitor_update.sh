#!/usr/bin/env bash


# wlr-randr --output DP-1 --on

SECONDARY_NOMITOR_NAME="DP-1"

# Check if ddcutil is installed
if ! command -v ddcutil &>/dev/null; then
	echo "ddcutil is not installed. Please install ddcutil to use this script."
	exit 1
fi

# Use ddcutil to detect displays
displays=$(ddcutil detect | grep "Display")

# Check if more than one display is detected
if [[ $(echo "$displays" | grep -c "Display") -gt 0 ]]; then
	ddcutil setvcp 0xD6 0x01
	# wlr-randr --output "$SECONDARY_NOMITOR_NAME" --on -right-of eDP
else
	ddcutil setvcp 0xD6 0x05
	# wlr-randr --output "$SECONDARY_NOMITOR_NAME" --off
fi
# .config/polybar/launch.sh --forest &
# xinput map-to-output 11 eDP
# xinput map-to-output 12 eDP
# xinput map-to-output 13 eDP
brightness -i 0 # update the brightness of the secondary monitor

