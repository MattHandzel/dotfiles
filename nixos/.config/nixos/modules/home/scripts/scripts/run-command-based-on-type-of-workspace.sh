#!/usr/bin/env bash

# Define the path to the shared_variables.nix file
NIXOS_ROOT_DIR="~/dotfiles/nixos/.config/nixos/"
NIX_FILE="$(eval echo $NIXOS_ROOT_DIR)shared_variables.nix"

# Extract the singletonApplications array from the nix file
singletonApplications=$(nix eval --json -f $NIX_FILE singletonApplications | jq -r '.[]')

# Get the current Hyprland workspace name
current_workspace=$(hyprctl activewindow | grep workspace | awk '{print $3}' | sed -E 's/\((\w*)\)/\1/g')

# Get the command line arguments
command_in_array=$2
command_not_in_array=$1

# Check if the current workspace name is in the singletonApplications array
if echo "${singletonApplications}" | grep -wq "${current_workspace}"; then
  # Run the first command if the workspace is in the array
  eval "$command_in_array"
else
  # Run the second command if the workspace is not in the array
  eval "$command_not_in_array"
fi

