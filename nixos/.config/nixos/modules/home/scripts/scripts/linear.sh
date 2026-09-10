#!/usr/bin/env bash
# linear — Linear (linear.app) as a standalone desktop app window. Linear ships
# no Linux desktop build, so this is a Chromium --app PWA-style window (same
# pattern as the claude.ai / gemini launchers). Chromium auto-derives the window
# class from the URL host (→ chrome-linear.app__-Default), which contains
# "linear", so focus_app's substring match makes Super+Alt+L a singleton toggle
# and the Hyprland window rule routes it to its own workspace. (Don't pass
# --class: Chromium ignores it once a browser session for this profile already
# exists, and it breaks the --app window launch.)
exec systemd-run --user --slice=app-webapps.slice --scope -- \
  chromium --app="https://linear.app" \
  --user-data-dir="$HOME/.config/chromium-app" \
  --ozone-platform=wayland "$@"
