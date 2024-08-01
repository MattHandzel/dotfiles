#!/bin/bash

# Get the current brightness of the main device
main_brightness=$(brightnessctl g)

# Define a mapping function
# This example assumes a linear mapping, but you can modify it as needed
function map_brightness {
	local main_brightness=$1
	# Assuming both brightness ranges are 0-100
	# Modify this function according to your needs
	echo "$main_brightness"
}

# Map the main device's brightness to the secondary monitor's brightness
secondary_brightness=$(map_brightness $main_brightness)

# Set the brightness of the secondary monitor
# Replace 'display' with the correct identifier for your secondary monitor
ddcutil setvcp 10 $secondary_brightness

# Check if ddcutil executed successfully
if [ $? -eq 0 ]; then
	echo "Secondary monitor brightness set to $secondary_brightness."
else
	echo "Failed to set secondary monitor brightness."
fi
