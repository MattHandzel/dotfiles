#! /usr/bin/env bash

# --name is X11-only and macOS kitty rejects it outright ("Unknown flag:
# --name"), the same crash tasker.sh had. --title is the portable half.
kitty --hold --title notetaker --working-directory "$HOME/notes" sh -c "nvim ." 
