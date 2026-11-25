#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Screenshot Search
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🖼️
# @raycast.packageName Matt's helpers

# @raycast.description Fuzzy-pick a recent screenshot newest-first, then copy it, open it, or reveal its folder. Replaces SUPER+SHIFT+S.
# @raycast.author Matt Handzel

export PATH="$HOME/.local/bin:/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:$PATH"
exec screenshot-search
