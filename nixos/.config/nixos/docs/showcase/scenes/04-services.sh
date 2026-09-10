# The part that is actually unusual about this config: the service fleet.
#
# Most of the work in this repo is not theming, it is durable background
# services — focus enforcement, capture pipelines, watchdogs, sync. This scene
# shows them running rather than describing them.
#
# One full-width window on purpose: a half-width pane wraps unit lines and the
# result is unreadable. Output is filtered to this config's own units (the
# unfiltered list is mostly Blueman and gvfs) and hard-truncated to the pane.

SCENE_TITLE="The service fleet"
SCENE_CAPTION="Focus enforcement, capture pipelines, transcription and watchdogs — declared in the flake, supervised by systemd."
SCENE_SETTLE=5
SCENE_FONT_SIZE=17

MINE='focus|ntfy|lifelog|espanso|activitywatch|aw-|gdoc|whisper|canary|kokoro|btrfs|kanata|syncthing|tailscale|vicinae|linear|meeting|transcribe|kbd-relay|stuck-key|memwatch|claude'

scene_run() {
  wallpaper

  term units zsh -ic "
    print -P '%B%F{blue}── system units ──────────────────────────────────────────────────%f%b'
    systemctl list-units --type=service --state=running --no-pager --no-legend --plain 2>/dev/null \
      | rg -i '$MINE' | awk '{printf \"  %-44s \", \$1; \$1=\$2=\$3=\$4=\"\"; print substr(\$0,5)}' \
      | cut -c1-104 | head -18
    echo
    print -P '%B%F{blue}── user units ────────────────────────────────────────────────────%f%b'
    systemctl --user list-units --type=service --state=running --no-pager --no-legend --plain 2>/dev/null \
      | rg -i '$MINE' | awk '{printf \"  %-44s \", \$1; \$1=\$2=\$3=\$4=\"\"; print substr(\$0,5)}' \
      | cut -c1-104 | head -18
    echo
    print -P '%B%F{blue}── timers ────────────────────────────────────────────────────────%f%b'
    systemctl list-timers --no-pager --no-legend 2>/dev/null | cut -c1-104 | head -10
    exec zsh -i"
}
