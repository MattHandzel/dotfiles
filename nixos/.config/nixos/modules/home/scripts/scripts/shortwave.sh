#! /usr/bin/env bash
# Shortwave (AI email) as a desktop app.
#
# Shortwave ships web/iOS/Android only -- no Linux client -- so the web app is the
# route, same chromium --app wrapper as superhuman.sh/calendar.sh, sharing the
# chromium-app profile so the Google session carries over.
#
# Unlike Superhuman, Shortwave needs NO browser extension: app.shortwave.com is a
# real standalone web app, not an empty host page an extension injects into. So
# there is deliberately no entry for it in programs.chromium.extensions.
#
# NOTE: Shortwave connects Gmail/Google Workspace mailboxes only (it is built on
# the Gmail API). Like Superhuman it cannot take matt@matthandzel.com (Namecheap
# PrivateEmail, plain IMAP).

# macOS: the same site as a standalone Chrome app window (Chrome keeps the
# separate chromium-app profile, like the Linux --user-data-dir).
if [[ "$(uname)" == Darwin ]]; then
  exec open -na "Google Chrome" --args --app="https://app.shortwave.com" --user-data-dir="$HOME/.config/chromium-app"
fi

exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="https://app.shortwave.com" --user-data-dir="$HOME/.config/chromium-app" --ozone-platform=wayland --force-device-scale-factor=1.25 "$@"
