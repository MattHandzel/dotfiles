#!/usr/bin/env bash
# Cancellable "waiting" UI shown before a distracting app is allowed during focus
# mode. A real zenity window (NOT a notification) so you can change your mind:
#
#   exit 0  -> waited the full delay (or focus ended) -> proceed (open/focus app)
#   exit 1  -> you clicked Cancel -> do NOT open the app
#
# Usage: focus-delay-gate <app-label>
set -u

app="${1:-this app}"
DELAY="${FOCUS_DELAY_SECONDS:-10}"
FOCUS_MODE_FILE="/tmp/focus_mode"

# No focus mode -> no friction.
[ -e "$FOCUS_MODE_FILE" ] || exit 0

# macOS: a real dialog (not a notification) with a Cancel button that gives up
# by itself after the delay. "gave up:true" = waited it out -> proceed;
# Cancel makes osascript exit 1 -> do not open the app. Any other failure fails
# OPEN, same as the zenity path.
if [[ "$(uname)" == Darwin ]]; then
  out=$(/usr/bin/osascript -e 'on run argv' \
    -e 'display dialog ("Opening " & item 1 of argv & " in " & item 2 of argv & "s…  Cancel to stay focused.") with title "Focus Mode" buttons {"Cancel"} giving up after (item 2 of argv as integer) with icon caution' \
    -e 'end run' -- "$app" "$DELAY" 2>&1) || {
    case "$out" in *"User canceled"*) exit 1 ;; esac
  }
  exit 0
fi

# If zenity can't run, fail OPEN (don't lock the user out): wait the delay, proceed.
if ! command -v zenity >/dev/null 2>&1; then
  sleep "$DELAY"
  exit 0
fi

(
  for ((i = 0; i <= DELAY; i++)); do
    if [ ! -e "$FOCUS_MODE_FILE" ]; then
      echo 100
      echo "# Focus mode ended — opening…"
      break
    fi
    echo $((i * 100 / DELAY))
    echo "# Opening ${app} in $((DELAY - i))s…  Cancel to stay focused."
    sleep 1
  done
  # When Cancel closes zenity, the read end of this pipe is gone; the next echo
  # would spam "write error: Broken pipe" into the journal. Swallow the feeder's
  # stderr — SIGPIPE still terminates it cleanly.
) 2>/dev/null | zenity --progress \
  --title="Focus Mode" \
  --text="Opening ${app}…" \
  --width=400 --percentage=0 --auto-close 2>/dev/null

# zenity exits 1 ONLY on Cancel; 0 on auto-close at 100%; other codes = display
# error -> fail open (proceed) rather than lock the user out.
rc=${PIPESTATUS[1]}
[ "$rc" = "1" ] && exit 1
exit 0
