#!/usr/bin/env bash
# Relaunch AeroSpace when its server stops answering.
#
# AeroSpace 0.21.3-Beta dies on its own assertions (upstream issue #1311,
# "MacWindow is already unbound") and occasionally hangs. Both leave the Mac
# with NO window manager and no indication beyond a crash dialog on some other
# workspace — on 2026-09-15 it sat dead until Matt pasted the stacktrace into a
# session. Nothing else supervises it: `start-at-login` only covers boot, and
# login-items.nix deliberately stays out of AeroSpace's launch path.
#
# Two distinct failures, one probe:
#   crash — process gone, socket gone  -> relaunch as soon as it's confirmed
#   hang  — process alive, socket dead -> kill first, then relaunch
# The hang path waits longer because a heavy refresh can briefly not answer.
set -u

STATE="$HOME/.local/state/aerospace-watchdog"
FAILS="$STATE/consecutive-failures"
mkdir -p "$STATE"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
notify() { command -v notify-send >/dev/null 2>&1 && notify-send "$1" "$2" || true; }

# Cheapest command that requires a live server; --version always exits 0, so it
# cannot be used as the probe.
#
# The probe MUST be bounded. Against a hung server the CLI connects and then
# blocks forever, so an unbounded probe never returns and launchd just piles up
# stuck copies every 15 s while the machine stays without a WM — the hang case
# would silently never recover. Verified: 4 back-to-back runs against a
# SIGSTOP'd AeroSpace produced no output at all until it was resumed.
probe() {
  aerospace list-monitors >/dev/null 2>&1 &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 1
  fi
  wait "$pid"
}

if probe; then
  [ -s "$FAILS" ] && log "server answering again"
  : >"$FAILS"
  exit 0
fi

n=$(( $(cat "$FAILS" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$FAILS"

if pgrep -x AeroSpace >/dev/null 2>&1; then
  # Alive but not answering. Give a slow refresh 4 probes (~60 s) to finish.
  [ "$n" -lt 4 ] && { log "no response, process alive (probe $n/4)"; exit 0; }
  log "hung for ~60 s — killing AeroSpace"
  pkill -x AeroSpace || true
  sleep 3
  # A wedged process can sit on SIGTERM; `open -a` would then just re-activate
  # the corpse and the relaunch would "succeed" onto a dead server.
  if pgrep -x AeroSpace >/dev/null 2>&1; then
    log "SIGTERM ignored — SIGKILL"
    pkill -9 -x AeroSpace || true
    sleep 2
  fi
else
  # Crashed. One confirming probe, so a relaunch already underway isn't raced.
  [ "$n" -lt 2 ] && { log "process gone (probe $n/2)"; exit 0; }
fi

log "relaunching AeroSpace"
open -a AeroSpace
: >"$FAILS"

sleep 5
if probe; then
  log "relaunch OK"
  notify "AeroSpace restarted" "It died and the watchdog brought it back."
else
  log "relaunch FAILED — server still not answering"
  notify "AeroSpace is down" "Watchdog relaunch failed; needs a look."
fi
