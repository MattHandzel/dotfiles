#!/bin/bash

# Define the minimum xrandr brightness (usually 0.0)
min_xrandr_brightness=0.0

# Get the current brightness from brightnessctl
current_brightnessctl=$(brightnessctl g)

# Check if the current brightnessctl brightness is 0
if [ "$current_brightnessctl" -eq 0 ]; then
	# Get the current xrandr brightness
	xrandr_brightness=$(xrandr --verbose | grep -m 1 'Brightness:' | cut -f2 -d ' ')

	# Decrease xrandr brightness by a small amount, for example, 0.02
	new_xrandr_brightness=$(echo "$xrandr_brightness - 0.03" | bc)

	# Check if the new xrandr brightness is below the minimum
	if (($(echo "$new_xrandr_brightness < $min_xrandr_brightness" | bc -l))); then
		# If it is, set xrandr brightness to the minimum
		xrandr --output eDP --brightness $min_xrandr_brightness
	else
		# If not, set the new xrandr brightness
		xrandr --output eDP --brightness $new_xrandr_brightness
	fi
else
	# Decrease system brightness using brightnessctl
	brightnessctl set 3%-

	# Set xrandr output display brightness to 1
	xrandr --output eDP --brightness 1
fi
python3 secondary_monitor_brightness.py
