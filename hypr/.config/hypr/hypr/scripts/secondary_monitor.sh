#!/bin/bash

# Get active window ID
active_window_id=$(xdotool getactivewindow)

# Get geometry of the active window
active_window_geometry=$(wmctrl -lG | grep $active_window_id)

# Parse geometry
read -r id desktop x y w h hostname title <<<"$active_window_geometry"

# Your secondary monitor position and resolution (update these values)
secondary_monitor_x=1920 # X position where secondary monitor starts
secondary_monitor_y=0    # Y position where secondary monitor starts
secondary_monitor_width=1920
secondary_monitor_height=1080

# Check if the active window is on the secondary monitor
if [ "$x" -ge "$secondary_monitor_x" ] && [ "$y" -ge "$secondary_monitor_y" ] &&
	[ "$x" -lt "$(($secondary_monitor_x + $secondary_monitor_width))" ] &&
	[ "$y" -lt "$(($secondary_monitor_y + $secondary_monitor_height))" ]; then
	echo "Active window is on the secondary monitor."
else
	echo "Active window is not on the secondary monitor."
fi
