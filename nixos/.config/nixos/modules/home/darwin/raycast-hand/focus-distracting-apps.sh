#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Distracting Apps List
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🚫
# @raycast.packageName Matt's helpers

# @raycast.description Print the apps Focus Mode delays by 15 s (from resources/focus-mode-apps.md — separate from the DNS blocklist).
# @raycast.author Matt Handzel

export PATH="$HOME/.local/bin:/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:$PATH"
exec focus-distracting-apps
