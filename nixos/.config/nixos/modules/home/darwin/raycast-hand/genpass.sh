#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Generate Password
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 🔑
# @raycast.packageName Matt's helpers
# @raycast.argument1 { "type": "dropdown", "placeholder": "kind", "optional": true, "data": [{"title": "passphrase, 6 words", "value": "words6"}, {"title": "passphrase, 4 words", "value": "words4"}, {"title": "random chars, 20", "value": "chars"}] }
# @raycast.argument2 { "type": "text", "placeholder": "how many (default 5)", "optional": true }

# @raycast.description Generate passphrases (default six words) or a random-character password, and print the candidates.
# @raycast.author Matt Handzel

export PATH="$HOME/.local/bin:/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:$PATH"
n="${2:-5}"
case "${1:-words6}" in
  words4) exec genpass -w 4 -n "$n" ;;
  chars)  exec genpass --chars -l 20 -n "$n" ;;
  *)      exec genpass -w 6 -n "$n" ;;
esac
