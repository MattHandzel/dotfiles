#! /usr/bin/env bash

# --name is an X11/Wayland concept (it sets WM_CLASS) and kitty on macOS
# rejects it outright with "Unknown flag: --name", so the whole script died
# before opening anything. --title is the portable half, and it is also what
# the AeroSpace binding matches on:
#   alt-ctrl-t = focus-app --title tasker -- tasker
kitty --hold --title tasker zsh -c "nvim -c 'Tw'" 

# # Function to sync vdirsyncer and calcurse
# sync_calendars() {
#     echo "Syncing calendars..."
#     # Import all of the calendars
#     vdirsyncer sync
#     # for file in "$HOME/.calendars"/*
#     # do
#     #   echo "Processing $file"
#     #   if [ -f "$file" ]; then
#     #     calcurse --import "$file"
#     #   fi
#     # done
#     calcurse -r 
# }
#
# # Sync immediately upon running the script
# sync_calendars
#
# # Run calcurse and sync every 5 minutes while it's running
# while true; do
#     kitty --hold --title calendar --name calendar sh -c "calcurse" 
#
#     # Start a background process to sync every 5 minutes
#     while pgrep -x "calcurse" > /dev/null; do
#         sync_calendars
#         sleep 600 # Sleep for 5 minutes (300 seconds)
#     done
#
#     break
# done
