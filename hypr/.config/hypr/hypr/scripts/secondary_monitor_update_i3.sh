#!/bin/bash

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
	xrandr --output DisplayPort-0 --auto --right-of eDP
	echo "A secondary monitor is connected."
	python3 secondary_monitor_brightness.py
else
	xrandr --output DisplayPort-0 --off
	echo "No secondary monitor detected."
fi
# .config/polybar/launch.sh --forest &
# xinput map-to-output 11 eDP
# xinput map-to-output 12 eDP
# xinput map-to-output 13 eDP
