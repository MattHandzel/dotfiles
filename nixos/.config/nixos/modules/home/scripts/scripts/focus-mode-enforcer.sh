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

CANCEL_COOLDOWN="${FOCUS_CANCEL_COOLDOWN:-45}"

# Unlock/deny state lives on disk, not in bash associative arrays. Two reasons,
# both bugs we actually hit:
#   1. `${#arr[@]}` on a declared-but-empty associative array trips `set -u`
#      (bash 5.3), which killed the service on the first event after Focus Mode
#      turned off — 58 restarts in one session.
#   2. systemd restarts this unit freely (socat drops, Hyprland reloads). In-memory
#      state meant every restart re-nagged you for apps you had already waited out.
# Files survive both. XDG_RUNTIME_DIR is tmpfs and cleared at logout.
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/focus-enforcer"
UNLOCK_DIR="$STATE_DIR/unlocked"
DENY_DIR="$STATE_DIR/denied"
mkdir -p "$UNLOCK_DIR" "$DENY_DIR"

# Addresses are like 0x5601ccf84850 — already safe as filenames, but be strict.
sane_addr() { printf '%s' "${1//[^0-9a-fA-Fx]/}"; }

socat -U - "UNIX-CONNECT:$socket" 2>/dev/null | while IFS= read -r line; do
  # Idle when Focus Mode is off; clear remembered unlocks + cancellations.
  if [ ! -e "$FOCUS_MODE_FILE" ]; then
    rm -f "$UNLOCK_DIR"/* "$DENY_DIR"/* 2>/dev/null || true
    continue
  fi

  # activewindowv2 carries the window ADDRESS. The older activewindow event
  # carries only class,title — pairing it with a separate `hyprctl activewindow`
  # call raced against queued events and could record the unlock against the
  # WRONG window, which re-gated an app you had just cleared. Take the address
  # from the event and derive the class from it, so both always describe the
  # same window.
  case "$line" in
    activewindowv2'>>'*) : ;;
    *) continue ;;
  esac

  addr="$(sane_addr "${line#activewindowv2>>}")"
  [ -n "$addr" ] || continue
  case "$addr" in 0x*) : ;; *) addr="0x$addr" ;; esac

  class="$(hyprctl clients -j 2>/dev/null |
    jq -r --arg a "$addr" '.[] | select(.address == $a) | .class // empty')"
  [ -n "$class" ] || continue

  is_distracting "$class" || continue

  [ -e "$UNLOCK_DIR/$addr" ] && continue # already cleared this window

  # You cancelled this window's gate recently → don't nag again. The app keeps
  # re-acquiring focus on its own (an email client raising itself, or focus
  # returning to it when the zenity dialog closed), which used to re-open the
  # gate on a loop. Silently bounce away until the cooldown lapses; only a
  # deliberate re-focus after that re-opens the gate.
  if [ -e "$DENY_DIR/$addr" ]; then
    last_denied="$(stat -c %Y "$DENY_DIR/$addr" 2>/dev/null || echo 0)"
    if [ "$(($(date +%s) - last_denied))" -lt "$CANCEL_COOLDOWN" ]; then
      hyprctl dispatch focuscurrentorlast >/dev/null 2>&1
      while IFS= read -r -t 0.3 _stale; do :; done
      continue
    fi
    rm -f "$DENY_DIR/$addr" 2>/dev/null || true # cooldown lapsed
  fi

  log "distracting app '$class' ($addr) focused → cancellable ${FOCUS_DELAY_SECONDS:-10}s gate"
  # Bounce away first so the app isn't usable behind the dialog.
  hyprctl dispatch focuscurrentorlast >/dev/null 2>&1

  if focus-delay-gate "$class"; then
    # Waited it out (or focus ended) → allow + refocus.
    if [ -e "$FOCUS_MODE_FILE" ]; then
      # Record the unlock BEFORE refocusing: the refocus generates its own
      # activewindowv2 event, and if that is read before the marker exists the
      # gate re-fires immediately — the "opens for a split second, then asks
      # again" symptom.
      : >"$UNLOCK_DIR/$addr"
      hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1
      log "unlocked '$class' ($addr)"
    fi
  else
    : >"$DENY_DIR/$addr"
    log "user cancelled opening '$class' — staying focused (${CANCEL_COOLDOWN}s cooldown)"
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
