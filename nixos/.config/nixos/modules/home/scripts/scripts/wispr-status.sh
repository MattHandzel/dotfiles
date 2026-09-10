#!/usr/bin/env bash
# Waybar module: is Wispr Flow running, and is it dictating right now?
#
# Wispr's own "Status" pill is easy to miss (it lives on one monitor and one
# workspace), so the bar carries the state instead. Idle Wispr holds no capture
# stream, so a live PipeWire Stream/Input/Audio node owned by one of its PIDs is
# a truthful "recording now" signal — not merely "the app is alive".
set -uo pipefail

# Every Wispr child (main, renderers, gpu, the linux-helper) carries this path in
# its cmdline; the bwrap wrapper does not, so this is the app's real PID set.
pids=$(pgrep -f 'usr/lib/wispr-flow' 2>/dev/null | paste -sd, -)

if [[ -z ${pids:-} ]]; then
  # Empty text hides the module: nothing to see when Wispr isn't running.
  printf '%s\n' '{"text":"","class":"off","tooltip":"Wispr Flow not running"}'
  exit 0
fi

# state must be "running": Wispr keeps an *armed* capture node around while idle
# (observed ~54s with the mic device closed), so a node's mere existence would
# light up REC when nothing is being recorded.
recording=$(pw-dump 2>/dev/null | jq -r --arg pids "$pids" '
  ($pids | split(",")) as $p
  | [ .[]
      | select(.type == "PipeWire:Interface:Node")
      | select(.info.state == "running")
      | .info.props
      | select(.["media.class"] == "Stream/Input/Audio")
      | select((.["application.process.id"] | tostring) | IN($p[]))
    ] | length' 2>/dev/null)

if [[ ${recording:-0} -gt 0 ]]; then
  printf '%s\n' '{"text":"  REC","class":"recording","tooltip":"Wispr Flow — dictating (mic live)"}'
else
  printf '%s\n' '{"text":"","class":"idle","tooltip":"Wispr Flow running (idle) — click to open the Hub"}'
fi
