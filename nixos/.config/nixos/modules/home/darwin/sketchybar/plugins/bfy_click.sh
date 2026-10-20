#!/bin/sh
# built-for-you: one use line per click on a SketchyBar item, so the use check
# (~/Obsidian/Main/scripts/built-for-you/usecheck.py) can tell whether Matt uses
# an item Claude built. Same shape as registry.log_use(): {"ts","id","src","what"},
# id "sketchybar:<item name>" ($NAME, set by SketchyBar). Item names and times only.
d="$HOME/.local/state/built-for-you"
mkdir -p "$d"
printf '{"ts":"%s","id":"sketchybar:%s","src":"sketchybar","what":"click"}\n' \
  "$(date +%Y-%m-%dT%H:%M:%S%z | sed -E 's/([0-9]{2})$/:\1/')" "$NAME" >> "$d/use-$(date +%F).jsonl"
