#!/usr/bin/env bash
# Meeting-recording pill: red "🎙 REC 1h 05m <name>" while the Raycast
# "Record Meeting (toggle)" job (launchd label com.matth.meeting-rec) is
# running, hidden otherwise.
#
# Added 2026-11-04 (Oops 20261102-201725): a recording started 2026-11-03 13:31
# was never toggled off and ran for 19 h at ~85 % of a core, with nothing on
# screen saying the mic was being recorded. The recorder now also stops itself
# after 3 h (raycast-scripts.nix, record-meeting).
#
# State: the job's presence in `launchctl list`, and
# ~/.local/state/meeting-rec.name (the output path, written at start; its
# mtime = start time). Refreshed every 30 s and on `meeting_rec_update`, which
# the Raycast script fires on start and stop and the recorder fires on auto-stop.
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"
SB=/opt/homebrew/bin/sketchybar
NAMEFILE="$HOME/.local/state/meeting-rec.name"

if ! /bin/launchctl list com.matth.meeting-rec >/dev/null 2>&1; then
  $SB --set "$NAME" drawing=off
  exit 0
fi

label="REC"
if [ -f "$NAMEFILE" ]; then
  start=$(/usr/bin/stat -f %m "$NAMEFILE")
  s=$(( $(/bin/date +%s) - start ))
  [ "$s" -lt 0 ] && s=0
  name=$(basename "$(/bin/cat "$NAMEFILE")" .wav)
  name=${name#????-??-??_??-??-??_}
  [ "$name" = meeting ] && name=""
  label=$(printf 'REC %dh %02dm%s' $((s / 3600)) $((s % 3600 / 60)) "${name:+ $name}")
fi
$SB --set "$NAME" drawing=on label="$label"
