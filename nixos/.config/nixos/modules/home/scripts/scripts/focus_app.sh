#!/usr/bin/env bash

# Check if the class name is provided as an argument
if [ -z "$1" ]; then
  echo "Usage: $0 <class_name>"
  exit 1
fi

# Get the class name from the input parameter
class_name="$1"

# Focus Mode friction: if focus mode is ON (/tmp/focus_mode exists) and this is a
# distracting app, show a cancellable wait UI (focus-delay-gate) before the app
# is focused/launched. Cancel → abort (you changed your mind); wait it out →
# proceed. The distracting list comes from ~/notes/resources/dns-blocklist.md via
# focus-distracting-apps, shared with focus-mode-enforcer.sh.
FOCUS_MODE_FILE="/tmp/focus_mode"
if [ -e "$FOCUS_MODE_FILE" ]; then
  distracting_re="$(focus-distracting-apps 2>/dev/null)"
  if [ -n "$distracting_re" ] && printf '%s' "$class_name" | grep -qiE "$distracting_re"; then
    focus-delay-gate "$class_name" || exit 0 # cancelled → don't open the app
  fi
fi

# Use hyprctl to list all clients and filter by the class name
window_id=$(hyprctl clients | grep -Ei "class:.*$class_name" | sed -n 's/.*class: *\([^ ]*\).*/\1/p' | sed -n '1p')
# .*title: *([^ ]*).*
# window_id=$(hyprctl clients | grep -Ei "class:.*$class_name")


# Check if a window with the specified class name was found
if [ -n "$window_id" ]; then
  # Focus the window
  hyprctl dispatch focuswindow "class:($window_id)"
  # echo "Focused window with class: $class_name"
else

  # Anchor the app name to the START of the title value. A loose substring match
  # (title:.*$class_name) wrongly matched e.g. GIMP's "RGB 8-bit non-linear
  # integer" title for class_name=linear, focusing GIMP instead of launching
  # Linear. Real title-only apps (btop/yazi) put their name first in the title.
  window_id=$(hyprctl clients | grep -Ei "title: +$class_name" | sed -n 's/.*title: *\([^ ]*\).*/\1/p' | sed -n '1p')
  if [ -n "$window_id" ]; then 
    hyprctl dispatch focuswindow "title:($window_id)"
  else

    # If not found then run the application
    # Try a -gui wrapper first (for TUI apps that need a terminal)
    if command -v "${class_name}-gui" &>/dev/null; then
      "${class_name}-gui" &
    else
      $class_name &
    fi

  fi


  # echo "No window found with class: $class_name"
fi
