#!/usr/bin/env bash

# macOS: no swaybg; set every desktop's picture through System Events.
if [[ "$(uname)" == Darwin ]]; then
  exec /usr/bin/osascript -e 'on run argv' \
    -e 'tell application "System Events" to set picture of every desktop to POSIX file (item 1 of argv)' \
    -e 'end run' -- "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
fi

PIDS=$(pgrep -f "swaybg")

swaybg -m fill -i $1 &

if [ -n "$PIDS" ]; then
  echo "$PIDS" | xargs kill
fi
