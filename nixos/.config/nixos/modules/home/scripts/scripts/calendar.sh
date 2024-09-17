#! /usr/bin/env bash

# Function to sync vdirsyncer and calcurse
sync_calendars() {
    echo "Syncing calendars..."
    vdirsyncer sync
    calcurse -r # Refresh calcurse to load the latest data
}

# Sync immediately upon running the script
sync_calendars

# Run calcurse and sync every 5 minutes while it's running
while true; do
    # Launch calcurse
    calcurse
    
    # Start a background process to sync every 5 minutes
    while pgrep -x "calcurse" > /dev/null; do
        sync_calendars
        sleep 300 # Sleep for 5 minutes (300 seconds)
    done
    
    # If calcurse exits, break out of the loop
    break
done
