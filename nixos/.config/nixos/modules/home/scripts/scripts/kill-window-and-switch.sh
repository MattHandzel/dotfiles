#!/usr/bin/env bash

# Close a singleton-application window and return to the workspace it was
# opened from.
#
# Singletons live on their own NAMED workspace (see singletonApplications in
# shared_variables.nix), so closing the window leaves you stranded on an empty
# workspace unless something moves you off it.
#
# This used to be `hyprctl dispatch workspace e-2` followed by `workspace e-1`
# — two backward jumps where only one was intended. With a single monitor the
# second jump was silently absorbed, because `e-1` clamps once you are already
# on the lowest existing workspace. Connect a second monitor and its workspaces
# become valid landing spots, so the second jump lands, and focus overshoots to
# the workspace *before* the one you came from.
#
# The order below sidesteps relative jumps entirely: leave FIRST (while
# Hyprland's previous-workspace pointer still refers to where we came from),
# then close the window by address. Closing after leaving also means Hyprland
# never has to pick a fallback focus for an emptied workspace, which is what
# made the old behaviour monitor-count dependent in the first place.

# macOS/AeroSpace: same idea — if this is the workspace's only window, go back
# to the previous workspace first, then close the window by id.
if [[ "$(uname)" == Darwin ]]; then
  wid=$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null | head -n1)
  count=$(aerospace list-windows --workspace focused 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$count" == 1 && -n "$wid" ]]; then
    aerospace workspace-back-and-forth
    exec aerospace close --window-id "$wid"
  fi
  exec aerospace close
fi

window_count=$(hyprctl activeworkspace -j | jq -r '.windows')
address=$(hyprctl activewindow -j | jq -r '.address')

if [ "$window_count" = "1" ] && [ -n "$address" ] && [ "$address" != "null" ]; then
  hyprctl dispatch workspace previous
  hyprctl dispatch closewindow "address:$address"
else
  hyprctl dispatch killactive ""
fi
