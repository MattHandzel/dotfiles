#!/bin/bash

# Define the maximum xrandr brightness (usually 1.0)
max_xrandr_brightness=1.0

# Get the current and maximum brightness from brightnessctl
current_brightnessctl=$(brightnessctl g)
max_brightnessctl=$(brightnessctl m)

xrandr_brightness=$(xrandr --verbose | grep -m 1 'Brightness:' | cut -f2 -d ' ')
# Check if the current brightnessctl brightness is not at maximum
if [ "$current_brightnessctl" -eq "0" ]; then
	# Increase system brightness using brightnessctl

	if [ "$(echo "$xrandr_brightness < 1" | bc)" -eq "1" ]; then
		# Increase xrandr brightness by a small amount, for example, 0.02
		new_xrandr_brightness=$(echo "$xrandr_brightness + 0.03" | bc)
		# Check if the new xrandr brightness is above the maximum
		if (($(echo "$new_xrandr_brightness > $max_xrandr_brightness" | bc -l))); then
			# If it is, set xrandr brightness to the maximum
			xrandr --output eDP --brightness $max_xrandr_brightness
		else
			# If not, set the new xrandr brightness
			xrandr --output eDP --brightness $new_xrandr_brightness
		fi
	else
		brightnessctl set +2%
	fi
else
	if [ "$xrandr_brightness" -lt "1" ]; then
		# Increase xrandr brightness by a small amount, for example, 0.02

		new_xrandr_brightness=$(echo "$xrandr_brightness + 0.03" | bc)
		# Check if the new xrandr brightness is above the maximum
		if (($(echo "$new_xrandr_brightness > $max_xrandr_brightness" | bc -l))); then
			# If it is, set xrandr brightness to the maximum
			xrandr --output eDP --brightness $max_xrandr_brightness
		else
			# If not, set the new xrandr brightness
			xrandr --output eDP --brightness $new_xrandr_brightness
		fi
	else
		brightnessctl set +3%
	fi
fi
python3 secondary_monitor_brightness.py
