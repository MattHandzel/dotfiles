#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Link Search
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔗
# @raycast.packageName Matt's helpers

# @raycast.description Fuzzy-search saved links and open the one you pick.
# @raycast.author Matt Handzel

export PATH="$HOME/.local/bin:/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:$PATH"
exec link-search
