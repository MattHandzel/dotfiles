#!/usr/bin/env bash

# Check if the class name is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <class_name> [target_workspace]"
  exit 1
fi

# Get the class name and optional target workspace from the input parameters
class_name="$1"
target_workspace="$2"

# Use hyprctl to list all clients and filter by the class name or title
# We use jq to parse the JSON output from hyprctl for more reliable matching
window_info=$(hyprctl clients -j | jq -r ".[] | select((.class | test(\"$class_name\"; \"i\")) or (.title | test(\"$class_name\"; \"i\"))) | \"\(.address) \(.workspace.name)\"" | head -n 1)

if [ -n "$window_info" ]; then
  # Split window_info into address and workspace
  read -r address workspace <<< "$window_info"
  
  # Switch to the workspace and focus the window
  # We always prepend name: because workspace.name from hyprctl gives the raw name/id
  # and dispatch workspace requires name: for named workspaces (and accepts it for IDs)
  hyprctl dispatch workspace "name:$workspace"
  hyprctl dispatch focuswindow "address:$address"
else
  # If not found then run the application
  # Check if a -gui wrapper exists (e.g. for TUI apps like yazi/btop)
  if command -v "${class_name}-gui" &> /dev/null; then
    "${class_name}-gui" &
  else
    $class_name &
  fi
  
  # If a target workspace was provided, switch to it so the user is there when it opens
  if [ -n "$target_workspace" ]; then
    # target_workspace comes with "name:" prefix from config, so use it directly
    hyprctl dispatch workspace "$target_workspace"
  fi
fi