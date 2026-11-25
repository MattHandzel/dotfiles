#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Grammar Check
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ✍️
# @raycast.packageName Matt's helpers

# @raycast.description Run LanguageTool over the current selection, or the clipboard when nothing is selected. Replaces SUPER+C.
# @raycast.author Matt Handzel

export PATH="$HOME/.local/bin:/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:$PATH"
exec grammar-check
