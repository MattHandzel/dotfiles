#!/usr/bin/env bash

# Check if the class name is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <class_name>"
  exit 1
fi

# Get the class name from the input parameter
class_name="$1"

# Use hyprctl to list all clients and filter by the class name
window_id=$(hyprctl clients | grep -Ei "class:.*$class_name" | sed -n 's/.*class: *\([^ ]*\).*/\1/p' | sed -n '1p')
# window_id=$(hyprctl clients | grep -Ei "class:.*$class_name")


# Check if a window with the specified class name was found
if [ -n "$window_id" ]; then
  # Focus the window
  hyprctl dispatch focuswindow "class:($window_id)"
  # echo "Focused window with class: $class_name"
else
  # If not found then run the application
  $class_name &

  # echo "No window found with class: $class_name"
fi
