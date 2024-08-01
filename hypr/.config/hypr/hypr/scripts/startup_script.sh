#!/usr/bin/env bash

# swww init 
# swww img "~/Wallpapers/mountain.jpg"
# nm-applet --indicator &

# data tracking stuff

aw-server &
aw-watcher-window &
aw-watcher-afk &

~/.config/hyprdots/scripts/volumecontrol.sh -o m
