#!/usr/bin/env bash
# ntfy-desktop-sub — surface ntfy messages as native desktop notifications.
#
# Subscribes to several topics on Matt's ntfy server at once and pops a swaync
# notification for each incoming message. Run as an always-on systemd user
# service. The ntfy CLI passes message fields to the handler as env vars
# ($message, $title, $topic, $priority).
#
# NOTE: the `ntfy` name is a zsh *function* (curl wrapper) in interactive shells,
# but inside this systemd service only the real ntfy-sh binary is on PATH, so
# `ntfy subscribe` works here.
set -u

# Explicit http:// scheme — the server is plain HTTP; without it the ntfy CLI
# defaults to HTTPS and the connection fails ("server gave HTTP response to
# HTTPS client").
NTFY_BASE="${NTFY_BASE:-http://server.matthandzel.com:8124}"
TOPICS="${NTFY_TOPICS:-claude,focus-mode,captures,capture}"

# Per-message handler (invoked by `ntfy subscribe ... <cmd>`).
if [[ "${1:-}" == "--handle" ]]; then
  title="${title:-${ntfy_title:-}}"
  msg="${message:-${ntfy_message:-}}"
  topic="${topic:-${ntfy_topic:-ntfy}}"
  prio="${priority:-3}"
  [[ -n "$title" ]] || title="ntfy: $topic"
  # Map ntfy priority (1..5) → notify-send urgency. Keep routine ones normal so
  # they auto-dismiss (per Matt's swaync timeout-critical=0 setup).
  urgency="normal"
  [[ "$prio" -ge 5 ]] 2>/dev/null && urgency="critical"
  [[ "$prio" -le 1 ]] 2>/dev/null && urgency="low"
  exec notify-send -u "$urgency" -i dialog-information -a "ntfy ($topic)" "$title" "$msg"
fi

# Subscriber: a multi-topic subscription. ntfy supports comma-separated topics on
# one connection. Self-contained --handle re-invocation keeps it one file.
SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
exec ntfy subscribe "${NTFY_BASE}/${TOPICS}" "bash '$SELF' --handle"
