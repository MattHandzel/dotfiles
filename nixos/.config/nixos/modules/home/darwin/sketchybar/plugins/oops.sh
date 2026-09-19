#!/usr/bin/env bash
# Oops: a red life-ring with the number of live Claude repair sessions
# (tabs of the `tmux -L oops` session "oops", one per incident). Hidden when
# there are none. The
# Oops terminal is parked on the AeroSpace workspace "oops" (aerospace.nix), so
# this is how Matt knows a repair is running without seeing its window:
# click = go to that workspace, or reopen the window if it was closed.
#
# Refreshed on the `oops_update` event (fired by ~/.local/bin/oops when it
# starts a session) and every 10 s, which is how a finished session drops off.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"
SB=/opt/homebrew/bin/sketchybar
AEROSPACE=/opt/homebrew/bin/aerospace

TMUX=""
for c in /etc/profiles/per-user/matth/bin/tmux "$HOME/.nix-profile/bin/tmux" \
         /run/current-system/sw/bin/tmux /opt/homebrew/bin/tmux; do
  [ -x "$c" ] && { TMUX="$c"; break; }
done

if [ "${1:-}" = "click" ]; then
  # A new incident may have no kitty window yet (it opens on entering the
  # workspace, via the AeroSpace workspace hook), so pending counts as "go there".
  pending=""
  [ "$($TMUX -L oops show-options -qv -t '=oops:' @oops_pending 2>/dev/null)" = 1 ] && pending=1
  if [ -n "$pending" ] || $AEROSPACE list-windows --workspace oops 2>/dev/null | grep -q .; then
    # summon, not `workspace`: bring "oops" to the monitor Matt is on instead of
    # jumping to whichever monitor it last lived on (Oops 20260914-112258).
    $AEROSPACE summon-workspace oops
  else
    "$HOME/.local/bin/oops" --attach
  fi
  exit 0
fi

n=0
if [ -n "$TMUX" ]; then
  n="$($TMUX -L oops list-windows -a 2>/dev/null | grep -c .)"
fi
if [ "${n:-0}" -gt 0 ]; then
  $SB --set "$NAME" drawing=on label="$n" icon.color="$RED"
else
  $SB --set "$NAME" drawing=off
fi
