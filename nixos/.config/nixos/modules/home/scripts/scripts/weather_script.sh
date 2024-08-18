#!/bin/bash
LOCATION="Chicago"  # leave blank to auto-detect based on IP

# Get weather data using wttr.in
WEATHER=$(curl -s "wttr.in/$LOCATION?format=%C")
TEMP=$(curl -s "wttr.in/$LOCATION?format=%t")

# Map weather conditions to emojis
case "$WEATHER" in
    "Clear") ICON="☀️" ;;  # sun
    "Cloudy") ICON="☁️" ;;  # cloud
    "Rain") ICON="🌧️" ;;   # rain
    "Snow") ICON="❄️" ;;    # snow
    "Overcast") ICON="☁️" ;;    # snow
    *) ICON="🌈" ;;         # default
esac

# Output the weather data
echo "$TEMP"
