#!/usr/bin/env bash 

if [[ $1 == "pre" ]]; then
  pkill audio-log 
  pkill .aplay-wrapped
  
elif [[ $1 == "post" ]]; then
  

  pkill audio-log 
  pkill .aplay-wrapped
  pkill arecord
  /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/audio-log.sh
  #
  # # Directory to save the audio file
  # echo "Current time is $(date)"
  # OUTPUT_DIR="/home/matth/notes/life-logging/audio-logging"
  # mkdir -p "$OUTPUT_DIR"
  #
  # # Generate filename with the current date
  # FILENAME="$(date +"%Y-%m-%d_%H-%M-%S.%3N %Z").wav"
  # FILEPATH="$OUTPUT_DIR/$FILENAME"
  #
  # # Start recording
  #
  # sleep 2
  # echo "right before recording, current time is $(date)"
  # echo "Recording started. Saving to $FILEPATH. Press Ctrl+C to stop."
  #
  # arecord -D hw:1,0 -f cd "$FILEPATH"
  #
  # echo "Recording saved as $FILEPATH"
fi
