#!/usr/bin/env bash
# Nested headless compositor for e2e_drilldown.py. See that file for what it checks.
#
# Usage: e2e_drilldown.sh <python-with-numpy-scipy-pillow> [wl-kbptr-bin-dir]
#        KBSHOT_E2E_TOOLS=<env with sway+wtype> is prepended to PATH.
set -uo pipefail

PY="${1:?usage: e2e_drilldown.sh <python> [wl-kbptr-bin-dir]}"
BIN="${2:-}"
TOOLS="${KBSHOT_E2E_TOOLS:-}"
[ -n "$TOOLS" ] && PATH="$TOOLS/bin:$PATH"
[ -n "$BIN" ] && PATH="$BIN:$PATH"
export PATH

for need in sway wtype wl-kbptr; do
  command -v "$need" >/dev/null || { echo "e2e: $need not on PATH"; exit 2; }
done

HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$(mktemp -d)"
export XDG_RUNTIME_DIR="$RUN"
export WLR_BACKENDS=headless
export WLR_LIBINPUT_NO_DEVICES=1
export WLR_RENDERER=pixman
export XDG_SESSION_TYPE=wayland
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE

cleanup() {
  [ -n "${SWAY_PID:-}" ] && kill "$SWAY_PID" 2>/dev/null
  wait "${SWAY_PID:-}" 2>/dev/null
  rm -rf "$RUN" || true
}
trap cleanup EXIT

sway -c /dev/null >"$RUN/sway.log" 2>&1 &
SWAY_PID=$!

for _ in $(seq 1 60); do
  sock="$(ls "$RUN"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)"
  [ -n "$sock" ] && break
  sleep 0.25
done
[ -n "${sock:-}" ] || { echo "e2e: nested compositor never came up"; sed -n 1,20p "$RUN/sway.log"; exit 2; }
export WAYLAND_DISPLAY="$(basename "$sock")"
echo "e2e: nested compositor on $WAYLAND_DISPLAY (real session untouched)"

if command -v swaymsg >/dev/null; then
  read -r E2E_OUTPUT E2E_W E2E_H <<<"$(swaymsg -t get_outputs -r 2>/dev/null \
    | "$PY" -c 'import json,sys; o=json.load(sys.stdin)[0]; m=o["current_mode"]; print(o["name"], m["width"], m["height"])' 2>/dev/null)"
fi
export E2E_OUTPUT="${E2E_OUTPUT:-HEADLESS-1}" E2E_W="${E2E_W:-1280}" E2E_H="${E2E_H:-720}"
echo "e2e: output $E2E_OUTPUT ${E2E_W}x${E2E_H}"

exec "$PY" "$HERE/e2e_drilldown.py"
