#!/usr/bin/env bash

# macOS: Spotify is the player. Toggle it the same way: running → quit; else
# launch with shuffle + repeat on (audtool's repeat/shuffle toggles below).
if [[ "$(uname)" == Darwin ]]; then
  if pgrep -xq Spotify; then
    osascript -e 'tell application "Spotify" to quit'
  else
    open -a Spotify
    sleep 2
    osascript -e 'tell application "Spotify"' -e 'set shuffling to true' -e 'set repeating to true' -e 'end tell' 2>/dev/null || true
  fi
  exit 0
fi

if (ps aux | grep audacious | grep -v grep > /dev/null) then
    pkill audacious
else
    hyprctl dispatch exec "[workspace 5 silent] audacious -t"
    sleep 0.5
    audtool playlist-repeat-status |grep "on" || audtool playlist-repeat-toggle
    audtool playlist-shuffle-status|grep "on" || audtool playlist-shuffle-toggle
fi