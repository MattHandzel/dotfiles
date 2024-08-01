#!/bin/bash

wlr-randr --output DP-1 --on
python3 ./secondary_monitor_brightness.py

# .config/polybar/launch.sh --forest &
# xinput map-to-output 11 eDP
# xinput map-to-output 12 eDP
# xinput map-to-output 13 eDP
