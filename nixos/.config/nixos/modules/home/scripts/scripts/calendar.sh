#! /usr/bin/env bash


# macOS: the same site as a standalone Chrome app window (Chrome keeps the
# separate chromium-app profile, like the Linux --user-data-dir).
# The window is untitled when AeroSpace first sees it, so the untitled-Chrome
# float rule catches it; wait for the title, then tile it on `calendar`.
if [[ "$(uname)" == Darwin ]]; then
  open -na "Google Chrome" --args --app="https://calendar.google.com" --user-data-dir="$HOME/.config/chromium-app" \
    --no-first-run --no-default-browser-check
  command -v aerospace >/dev/null || exit 0
  for _ in $(seq 40); do
    id=$(aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null \
      | awk -F'|' '$2 == "Google Chrome" && tolower($3) ~ /google calendar/ && $3 !~ / - Google Chrome$/ {print $1; exit}')
    [[ -n "$id" ]] && break
    sleep 0.5
  done
  [[ -n "$id" ]] || exit 0
  aerospace layout --window-id "$id" tiling || true
  aerospace move-node-to-workspace --window-id "$id" calendar || true
  aerospace workspace calendar || true
  exec aerospace focus --window-id "$id"
fi

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="https://calendar.google.com" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland --force-device-scale-factor=1.25 "$@"

# # Function to sync vdirsyncer and calcurse
# sync_calendars() {
#     echo "Syncing calendars..."
#     # Import all of the calendars
#     vdirsyncer sync
#     # for file in "$HOME/.calendars"/*
#     # do
#     #   echo "Processing $file"
#     #   if [ -f "$file" ]; then
#     #     calcurse --import "$file"
#     #   fi
#     # done
#     calcurse -r 
# }
#
# # Sync immediately upon running the script
# sync_calendars
#
# # Run calcurse and sync every 5 minutes while it's running
# while true; do
#     kitty --hold --title calendar --name calendar sh -c "calcurse" 
#
#     # Start a background process to sync every 5 minutes
#     while pgrep -x "calcurse" > /dev/null; do
#         sync_calendars
#         sleep 600 # Sleep for 5 minutes (300 seconds)
#     done
#
#     break
# done
