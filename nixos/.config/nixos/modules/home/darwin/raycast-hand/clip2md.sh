#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Clipboard → Markdown
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📝
# @raycast.packageName Matt's helpers
# @raycast.argument1 { "type": "dropdown", "placeholder": "then", "optional": true, "data": [{"title": "convert in place", "value": "convert"}, {"title": "convert and paste (;;md)", "value": "paste"}] }

# @raycast.description Convert the rich text (HTML) on the clipboard to GitHub-flavoured Markdown with pandoc. "paste" also pastes it where the cursor is, like the espanso ;;md trigger did. Replaces SUPER+SHIFT+M.
# @raycast.author Matt Handzel

export PATH="$HOME/.local/bin:/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:$PATH"
if [ "${1:-convert}" = paste ]; then exec clip2md --paste; else exec clip2md; fi
