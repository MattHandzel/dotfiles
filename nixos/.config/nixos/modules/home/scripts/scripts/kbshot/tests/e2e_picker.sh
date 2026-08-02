#!/usr/bin/env bash
# End-to-end check of the picker's key handling, against the real patched binary.
#
# The three keys the hierarchy depends on -- a label character, Return, and
# BackSpace at the start of a round -- are handled inside wl-kbptr, in C, so no
# amount of Python testing says whether they work. This drives the actual binary.
#
# It runs in a NESTED headless sway on its own Wayland socket, never the live
# session. That is not tidiness: wl-kbptr takes an EXCLUSIVE layer-shell keyboard
# grab, so testing on the real compositor would take the keyboard away from
# whoever is using the machine. Keys are injected with the virtual-keyboard
# protocol through that socket, so they cannot reach the real session either.
#
# Usage: e2e_picker.sh [path-to-wl-kbptr-bin-dir]
set -uo pipefail

BIN="${1:-}"
TOOLS="${KBSHOT_E2E_TOOLS:-}"
[ -n "$TOOLS" ] && PATH="$TOOLS/bin:$PATH"
[ -n "$BIN" ] && PATH="$BIN:$PATH"
export PATH

for need in sway wtype wl-kbptr; do
  command -v "$need" >/dev/null || { echo "e2e: $need not on PATH"; exit 2; }
done

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

# Three areas, so a single character selects one and the label alphabet is
# exercised the same way the hierarchy uses it.
AREAS=$'200x100+0+0 40x30+0+0\n200x100+300+0 40x30+300+0\n200x100+0+200 40x30+0+200'

fails=0

# $1 name, $2 keys to send (wtype args), $3 expected stdout prefix, $4 expected exit
#
# The key is sent repeatedly until the picker exits, not once after a sleep. A
# single well-timed send is a coin flip: it is dropped if it lands before the
# layer surface has taken its keyboard grab, which showed up as this file passing
# on one run and timing out on the next. Repeats are harmless -- they arrive after
# the process is gone.
#
# $5 = 0 turns the repeat off, for the one probe whose point is that a SINGLE
# character is not a whole label: sending it twice would spell one and select.
probe() {
  local name="$1" keys="$2" want="$3" wantrc="$4" repeat="${5:-1}"
  local out rc pid i
  printf '%s\n' "$AREAS" | timeout 25 wl-kbptr \
      -p -o modes=floating \
      -o home_row_keys=asdfjkl\;qwe \
      -o mode_floating.source=stdin \
      -o mode_floating.label_symbols=ud \
      -o general.cancellation_status_code=1 >"$RUN/out.txt" 2>/dev/null &
  pid=$!
  sleep 0.8
  for i in $(seq 1 15); do
    kill -0 "$pid" 2>/dev/null || break
    # shellcheck disable=SC2086
    wtype $keys >/dev/null 2>&1
    sleep 0.7
    [ "$repeat" = 0 ] && break
  done
  wait "$pid"
  rc=$?
  out="$(head -1 "$RUN/out.txt" 2>/dev/null)"
  if [ "$rc" = "$wantrc" ] && [[ "$out" == "$want"* ]]; then
    echo "  PASS  $name -> exit $rc, stdout '$out'"
  else
    echo "  FAIL  $name -> exit $rc (wanted $wantrc), stdout '$out' (wanted '$want'*)"
    fails=$((fails + 1))
  fi
}

echo
echo "picker key handling (patched wl-kbptr):"
# 3 areas over a 2-symbol alphabet is a 2-character label, and the first typed
# character is the LEAST significant digit, so area 0 is "uu". Sending one "u" is
# what a half-typed label looks like: it must NOT select anything.
probe "a full label picks that area"      "-- uu"     "200x100+0+0"  0
probe "half a label selects nothing (control)" "-- u" ""             124  0
probe "Return reports ACCEPT"             "-k Return" "ACCEPT"       0
probe "BackSpace at the start reports BACK" "-k BackSpace" "BACK"    0
# Negative control: Escape must still be a plain cancellation, or ACCEPT/BACK
# would be indistinguishable from "the user gave up" and Enter would silently
# capture things the user meant to abandon.
probe "Escape is still a cancellation"    "-k Escape" ""             1

echo
if [ "$fails" = 0 ]; then
  echo "PASS: every picker key behaves as the hierarchy needs"
else
  echo "FAIL: $fails picker key check(s)"
fi
exit "$fails"
