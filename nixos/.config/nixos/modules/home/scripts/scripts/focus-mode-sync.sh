#!/usr/bin/env bash
# focus-mode-sync — make the laptop's Focus Mode follow the Life Scheduler
# calendar. Subscribes to the same ntfy `focus-mode` topic the server resolver
# (modules/core/focus-mode-resolver.nix) publishes mode transitions to, and
# drives /tmp/focus_mode via `toggle-focus-mode on|off`.
#
# Policy (chosen by Matt): CALENDAR WINS.
#   - Entering a Deep Work / Comms block        → force Focus ON.
#   - A manual "off" during a focus block        → re-asserted ON within ≤1
#     keepalive (~45s). You can't escape the block.
#   - The block ends (transition to Free)        → Focus OFF.
#   - During Free time, a manual Focus ON is left alone until the next block
#     boundary (voluntary focus is allowed).
#
# Robustness (this service must never wedge the laptop):
#   * Network/server down  → curl just exits; we sleep and retry. The flag is
#     NEVER changed on error, so the last known state holds (fail-safe).
#   * Started mid-block     → we stream with `since=12h`, replaying the most
#     recent transition so we converge to the right state on boot.
#   * Malformed message     → ignored; last good state kept.
#   * cal state still unknown (no message ever seen) → we touch nothing, leaving
#     full manual control.
# Logs: journalctl --user -u focus-mode-sync -f
set -u

NTFY_URL="${FOCUS_NTFY_URL:-http://server.matthandzel.com:8124}"
TOPIC="${FOCUS_NTFY_TOPIC:-focus-mode}"
FLAG="/tmp/focus_mode"

cal_want="" # "", "on", or "off" — "" = unknown → never touch the flag
since="all" # set to the last seen message id after catch-up, then stream live

log() { printf '%s focus-sync: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

mode_to_want() {
  case "$1" in
    deep_work | comms) printf 'on' ;;
    free) printf 'off' ;;
    *) printf '' ;;
  esac
}

# One-shot catch-up: read the cached history as a batch (poll=1 returns
# immediately and closes), take only the LAST focus-mode message, and converge to
# that state ONCE — no flapping through every historical transition, no replayed
# notification spam. Sets `cal_want` and advances `since` past the catch-up.
catch_up() {
  local last_mode="" last_id="" ev id mode
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    ev="$(printf '%s' "$line" | jq -r '.event // empty' 2>/dev/null)"
    id="$(printf '%s' "$line" | jq -r '.id // empty' 2>/dev/null)"
    [[ -n "$id" ]] && last_id="$id"
    [[ "$ev" == "message" ]] || continue
    mode="$(printf '%s' "$line" | jq -r '.message | fromjson? | .mode // empty' 2>/dev/null)"
    [[ -n "$mode" ]] && last_mode="$mode"
  done < <(curl -sN --max-time 30 "$NTFY_URL/$TOPIC/json?since=12h&poll=1" 2>/dev/null)

  [[ -n "$last_id" ]] && since="$last_id"
  local want
  want="$(mode_to_want "$last_mode")"
  if [[ -n "$want" ]]; then
    cal_want="$want"
    if [[ "$want" == "on" && ! -e "$FLAG" ]]; then
      log "catch-up: calendar $last_mode → focus ON"
      toggle-focus-mode on
    elif [[ "$want" == "off" && -e "$FLAG" ]]; then
      log "catch-up: calendar free → focus OFF"
      toggle-focus-mode off
    else
      log "catch-up: state already correct (cal=$want)"
    fi
  else
    log "catch-up: no prior focus-mode message; leaving manual control"
  fi
}

# Re-assert ON while the calendar wants focus (covers a manual cheat-off). Never
# force OFF here — that only happens on the explicit transition to Free, so a
# voluntary focus during Free time is preserved.
reconcile() {
  if [[ "$cal_want" == "on" && ! -e "$FLAG" ]]; then
    log "re-asserting focus ON (calendar block active)"
    toggle-focus-mode on
  fi
}

handle_mode() {
  local mode="$1" prev="$cal_want"
  case "$mode" in
    deep_work | comms) cal_want="on" ;;
    free) cal_want="off" ;;
    *) return ;; # unknown mode → ignore
  esac
  if [[ "$cal_want" == "on" ]]; then
    [[ -e "$FLAG" ]] || { log "calendar $mode → focus ON"; toggle-focus-mode on; }
  elif [[ "$cal_want" == "off" && "$prev" == "on" ]]; then
    [[ -e "$FLAG" ]] && { log "calendar free → focus OFF"; toggle-focus-mode off; }
  fi
}

log "subscribing to $NTFY_URL/$TOPIC"
# Converge to the latest known calendar state once, silently, before streaming.
catch_up

while true; do
  # Process substitution (not a pipe) so cal_want/since survive across reconnects.
  while IFS= read -r line; do
    [[ -n "$line" ]] || { reconcile; continue; }
    ev="$(printf '%s' "$line" | jq -r '.event // empty' 2>/dev/null)"
    case "$ev" in
      message)
        id="$(printf '%s' "$line" | jq -r '.id // empty' 2>/dev/null)"
        [[ -n "$id" ]] && since="$id"
        body="$(printf '%s' "$line" | jq -r '.message // empty' 2>/dev/null)"
        mode="$(printf '%s' "$body" | jq -r '.mode // empty' 2>/dev/null)"
        [[ -n "$mode" ]] && handle_mode "$mode"
        ;;
    esac
    reconcile # runs on every line incl. keepalive (~45s) → bounds the cheat window
  done < <(curl -sN --max-time 86400 "$NTFY_URL/$TOPIC/json?since=$since" 2>/dev/null)
  log "stream ended/unreachable; reconnecting in 5s (state held: cal=${cal_want:-unknown})"
  sleep 5
done
