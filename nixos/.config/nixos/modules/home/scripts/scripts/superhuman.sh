#! /usr/bin/env bash
# Superhuman as a desktop app.
#
# Superhuman ships macOS/Windows/iOS/Android clients but no Linux build, so the web
# app is the route. Same wrapper technique as calendar.sh, sharing the chromium
# profile so the Google session carries over.
#
# NOTE: Superhuman only connects Gmail/Google Workspace and Outlook/Microsoft 365
# mailboxes. It has no generic IMAP support, so matt@matthandzel.com (Namecheap
# PrivateEmail) cannot be added without moving that domain's mail hosting.

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="https://mail.superhuman.com" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland --force-device-scale-factor=1.25 "$@"
