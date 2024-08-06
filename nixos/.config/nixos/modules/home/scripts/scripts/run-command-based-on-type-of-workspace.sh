#!/bin/bash

# Define the path to the shared_variables.nix file
NIX_FILE="${NIXOS_ROOT_DIR}shared_variables.nix"

# Extract the singletonApplications array from the nix file
singletonApplications=$(nix eval --json -f $NIX_FILE singletonApplications | jq -r '.[]')

# Get the current Hyprland workspace name
current_workspace=$(hyprctl activewindow | grep workspace | awk '{print $2}')

# Get the command line arguments
command_not_in_array=$1
command_in_array=$2

# Check if the current workspace name is in the singletonApplications array
if echo "${singletonApplications[@]}" | grep -wq "${current_workspace}"; then
  # Run the first command if the workspace is in the array
  eval "$command_in_array"
else
  # Run the second command if the workspace is not in the array
  eval "$command_not_in_array"
fi

