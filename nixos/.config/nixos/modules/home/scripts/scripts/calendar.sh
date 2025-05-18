#! /usr/bin/env bash

# Function to sync vdirsyncer and calcurse
sync_calendars() {
    echo "Syncing calendars..."
    # Import all of the calendars
    vdirsyncer sync
    # for file in "$HOME/.calendars"/*
    # do
    #   echo "Processing $file"
    #   if [ -f "$file" ]; then
    #     calcurse --import "$file"
    #   fi
    # done
    calcurse -r 
}

# Sync immediately upon running the script
sync_calendars

# Run calcurse and sync every 5 minutes while it's running
while true; do
    kitty --hold --title calendar --name calendar sh -c "calcurse" 
    
    # Start a background process to sync every 5 minutes
    while pgrep -x "calcurse" > /dev/null; do
        sync_calendars
        sleep 600 # Sleep for 5 minutes (300 seconds)
    done
    
    break
done
