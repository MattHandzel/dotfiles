#!/usr/bin/env bash

# Check if an application name was provided
if [ "$#" -lt 1 ]; then
	echo "Usage: $0 <application>"
	exit 1
fi

APP_NAME=$1

# Try to focus the application window using wmctrl
# The -x option matches against the WM_CLASS property of the window
if ! wmctrl -x -a "$APP_NAME"; then
	# If wmctrl fails to find and focus the window, start a new instance
	if [ "$APP_NAME" = "googlecalendar-nativefier-e22938" ]; then
		/home/matthandzel/GoogleCalendar-linux-x64/GoogleCalendar &
	else
		"$APP_NAME" &
	fi

	# Initialize SECONDS to zero
	SECONDS=0
	# Loop until the application window is found or 10 seconds have passed
	while ! wmctrl -x -a "$APP_NAME"; do
		# Check if 10 seconds have passed
		if [ $SECONDS -ge 10 ]; then
			echo "Timeout reached: The application window was not found."
			break
		fi
		# Non-blocking command to avoid busy waiting
		read -t 0.1 -N 0
	done
fi

# Check for a second argument to enable fullscreen
if [ "$#" -eq 2 ] && [ "$2" = "fullscreen" ]; then
	i3-msg fullscreen enable
fi
