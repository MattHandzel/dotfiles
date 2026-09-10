#!/usr/bin/env bash
# Focus the Wispr Flow "Hub" window (launching the app if needed).
#
# Not focus_app: that matches on class alone, and Wispr ships TWO windows under
# class wispr-flow — "Hub" (the app) and "Status" (the floating dictation pill).
# Matching by class could focus the pill. Address-match the Hub explicitly.
set -uo pipefail

# macOS: Wispr Flow is a native app; `open -a` raises its Hub (or launches it).
if [[ "$(uname)" == Darwin ]]; then
  exec open -a "Wispr Flow"
fi

addr=$(hyprctl clients -j | jq -r '
  .[] | select(.class == "wispr-flow" and .title == "Hub") | .address' | head -n1)

if [[ -n ${addr:-} && $addr != "null" ]]; then
  hyprctl dispatch focuswindow "address:$addr"
else
  hyprctl dispatch exec wispr-flow
fi
