#!/usr/bin/env bash

# Check if an application name was provided
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <application>"
  exit 1
fi

APP_NAME="$1"

# Function to focus the application window using Hyprland client output
focus_window() {
  # Use hyprctl clients to list windows
  window_info=$(hyprctl clients)

  # Search for window based on title or class (adjust based on your preference)
  window_line=$(grep -E "(title|class): $APP_NAME" <<< "$window_info")

  # Check if window line is found
  if [ -n "$window_line" ]; then
    echo "window line is $window_line"
    # Extract window ID (assuming format "Window <ID> ->")
    window_id=$(echo "$window_line" | cut -d ' ' -f 2)

    # Focus the window using hyprctl dispatcher
    hyprctl dispatch focuswindow "$window_id"
    exit
  else
    echo "Window with title or class '$APP_NAME' not found."
  fi
}

# Try to focus the application window
  # If focusing fails, start a new instance
  if [ "$APP_NAME" = "googlecalendar-nativefier-e22938" ]; then
    /home/matthandzel/GoogleCalendar-linux-x64/GoogleCalendar &
  else
    "$APP_NAME" &
  fi

  # Initialize SECONDS to zero
  SECONDS=0
  # Loop until the application window is potentially focused or 10 seconds passed
  while [ $SECONDS -lt 10 ]; do
    # Non-blocking wait for potential window creation
    sleep 0.1 &
    wait $!
    # Attempt to focus again after a short wait
    focus_window
    SECONDS=$((SECONDS + 1))
  done

  if ! focus_window; then
    echo "Timeout reached: The application window was not found."
  fi
fi

# Check for fullscreen argument
# if [ "$#" -eq 2 ] && [ "$2" = "fullscreen" ]; then
#   # Use hyprctl dispatcher to toggle fullscreen
#   hyprctl dispatch togglefullscreen
# fi
