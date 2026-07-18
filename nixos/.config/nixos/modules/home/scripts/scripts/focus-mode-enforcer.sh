#!/usr/bin/env bash
# Focus Mode enforcer — cancellable "wait UI" friction for distracting apps.
#
# Runs as an always-on systemd user service, staying connected to Hyprland's
# event socket. It only ACTS when Focus Mode is ON (/tmp/focus_mode exists). When
# you focus a distracting app, it bounces focus away and opens a cancellable
# zenity countdown (focus-delay-gate): wait it out → the app is refocused; hit
# Cancel → you stay where you were (you changed your mind). Unlocks reset when
# Focus Mode turns off.
#
# The distracting list is derived from ~/notes/resources/dns-blocklist.md via
# `focus-distracting-apps` — one source of truth shared with focus_app + DNS.
#
# Logs: journalctl --user -u focus-mode-enforcer -f
set -u

FOCUS_MODE_FILE="/tmp/focus_mode"

log() { printf '%s focus-enforcer: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

find_socket() {
  local sig="${HYPRLAND_INSTANCE_SIGNATURE:-}" base d
  for base in "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" /tmp/hypr; do
    [ -d "$base" ] || continue
    if [ -n "$sig" ] && [ -S "$base/$sig/.socket2.sock" ]; then
      printf '%s' "$base/$sig/.socket2.sock"
      return 0
    fi
    d="$(ls -t "$base" 2>/dev/null | grep -v '\.lock$' | head -n1)"
    if [ -n "$d" ] && [ -S "$base/$d/.socket2.sock" ]; then
      export HYPRLAND_INSTANCE_SIGNATURE="$d"
      printf '%s' "$base/$d/.socket2.sock"
      return 0
    fi
  done
  return 1
}

# Distracting window classes, sourced from the blocklist markdown. Re-read on
# each focus event so edits to the list take effect without a restart.
is_distracting() {
  local class="$1" re
  re="$(focus-distracting-apps 2>/dev/null)"
  [ -n "$re" ] || return 1 # empty list → match nothing (never an empty regex)
  printf '%s' "$class" | grep -qiE "$re"
}

socket=""
for _ in $(seq 1 60); do
  socket="$(find_socket)" && [ -n "$socket" ] && break
  sleep 1
done
if [ -z "$socket" ]; then
  log "no Hyprland event socket found after 60s; exiting (systemd will retry)"
  exit 1
fi
log "connected to $socket (sig=${HYPRLAND_INSTANCE_SIGNATURE:-?})"

declare -A unlocked

socat -U - "UNIX-CONNECT:$socket" 2>/dev/null | while IFS= read -r line; do
  # Idle when Focus Mode is off; clear remembered unlocks.
  if [ ! -e "$FOCUS_MODE_FILE" ]; then
    [ "${#unlocked[@]}" -ne 0 ] && unlocked=()
    continue
  fi

  case "$line" in
    activewindow'>>'*) : ;;
    *) continue ;;
  esac

  payload="${line#activewindow>>}"
  class="${payload%%,*}"
  [ -n "$class" ] || continue

  is_distracting "$class" || continue

  addr="$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')"
  [ -n "$addr" ] || continue
  [ -n "${unlocked[$addr]:-}" ] && continue # already cleared this window

  log "distracting app '$class' ($addr) focused → cancellable ${FOCUS_DELAY_SECONDS:-10}s gate"
  # Bounce away first so the app isn't usable behind the dialog.
  hyprctl dispatch focuscurrentorlast >/dev/null 2>&1

  if focus-delay-gate "$class"; then
    # Waited it out (or focus ended) → allow + refocus.
    if [ -e "$FOCUS_MODE_FILE" ]; then
      unlocked[$addr]=1
      hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
      log "unlocked '$class' ($addr)"
    fi
  else
    log "user cancelled opening '$class' — staying focused"
  fi

  # focus-delay-gate blocks this read loop while its countdown is open, so
  # activewindow events pile up in the socket meanwhile: our own
  # focuscurrentorlast bounce, the refocus dispatch above, and any rapid user
  # focus switches. Processing that backlog re-fired the gate for every queued
  # distracting event (and ping-ponged between two distracting windows) — the
  # "loops multiple times" bug. Drain the stale backlog so only the next
  # *deliberate* focus change can re-trigger a gate. read -t returns fast when a
  # line is buffered and settles in ≤0.3s once the queue is empty.
  while IFS= read -r -t 0.3 _stale; do :; done
done

log "event stream ended; exiting (systemd will restart)"
