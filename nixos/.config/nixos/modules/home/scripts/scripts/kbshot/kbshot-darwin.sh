#!/usr/bin/env bash
# kbshot (macOS edition) — the same hotkeys, without the Wayland picker.
#
# The Linux kbshot labels every window / text block / rectangle and lets you type
# a label; that overlay is wl-kbptr + Hyprland geometry and has no macOS port.
# Here the region comes from `screencapture -i` (drag a box, or press SPACE to
# pick a whole window; ESC aborts). The flags keep their meaning:
#
#   kbshot             pick a region → PNG in ~/Pictures/Screenshots + clipboard
#   kbshot --ocr       pick a region → tesseract → text on the clipboard
#   kbshot --corners   same as plain (a drag IS the two-corner gesture here)
#   kbshot --abort     no overlay to clear on macOS; exits 0
#   kbshot --menu      choose: area / window / full screen / area→OCR
#   --no-copy / --no-save  as on Linux
set -uo pipefail

dir="${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
mode="area" ocr=0 copy=1 save=1 menu=0
for a in "$@"; do
  case "$a" in
    --ocr) ocr=1 ;;
    --corners | --words) ;;
    --abort) exit 0 ;;
    --menu) menu=1 ;;
    --no-copy) copy=0 ;;
    --no-save) save=0 ;;
    --window) mode="window" ;;
    --full) mode="full" ;;
    -h | --help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "kbshot: unknown flag $a" >&2; exit 2 ;;
  esac
done

if [ "$menu" = 1 ]; then
  pick=$(printf '%s\n' "Area (drag)" "Window (click)" "Full screen" "Area → OCR to clipboard" | choose -n 4 -p "kbshot ") || exit 0
  case "$pick" in
    "Area (drag)") mode=area ;;
    "Window (click)") mode=window ;;
    "Full screen") mode=full ;;
    "Area → OCR"*) mode=area; ocr=1 ;;
    *) exit 0 ;;
  esac
fi

mkdir -p "$dir"
stamp=$(date +'%Y-%m-%d-%Ih%Mm%Ss')
tmp=$(mktemp -t kbshot).png
case "$mode" in
  area) /usr/sbin/screencapture -i -o -x "$tmp" ;;
  window) /usr/sbin/screencapture -i -W -o -x "$tmp" ;;
  full) /usr/sbin/screencapture -x "$tmp" ;;
esac
[ -s "$tmp" ] || { rm -f "$tmp"; exit 0; } # ESC → nothing written

if [ "$ocr" = 1 ]; then
  text=$(tesseract "$tmp" stdout 2>/dev/null | awk 'NF' )
  rm -f "$tmp"
  if [ -z "$text" ]; then notify-send "kbshot" "No text recognised"; exit 1; fi
  printf '%s' "$text" | pbcopy
  notify-send "kbshot · OCR" "$(printf '%s' "$text" | head -c 120)"
  exit 0
fi

out="$dir/$stamp.png"
[ "$save" = 1 ] && cp "$tmp" "$out"
if [ "$copy" = 1 ]; then
  /usr/bin/osascript -e 'on run argv' -e 'set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)' -e 'end run' -- "$tmp"
fi
rm -f "$tmp"
msg="copied to clipboard"; [ "$save" = 1 ] && msg+=" · saved $(basename "$out")"
notify-send "kbshot" "$msg"
