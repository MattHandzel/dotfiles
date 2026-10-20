#!/usr/bin/env bash
# `EEE d MMM  HH:mm:ss` → "Thu 10 Sep  10:42:07". Two spaces between date and time
# on purpose: the time is the thing you glance at.
/opt/homebrew/bin/sketchybar --set "$NAME" label="$(/bin/date '+%a %-d %b  %H:%M:%S')"
