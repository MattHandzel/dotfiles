#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Tmux Sessionizer
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🗂️
# @raycast.packageName Matt's helpers

# @raycast.description Open the fzf project picker in a new kitty window and attach a tmux session for whatever you choose.
# @raycast.author Matt Handzel

export PATH="$HOME/.local/bin:/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:$PATH"
exec open -na kitty --args --title sessionizer -e tmux-sessionizer
