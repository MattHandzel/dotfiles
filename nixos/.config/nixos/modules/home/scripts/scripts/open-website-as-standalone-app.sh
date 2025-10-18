#/usr/bin/env bash

# Get the website name from the URL
app=$1

name=$(echo "$app" | awk -F[/:] '{print $4}' | sed 's/www.//;s/\..*//')

echo $name
exec chromium --app=$app --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland "$@"
