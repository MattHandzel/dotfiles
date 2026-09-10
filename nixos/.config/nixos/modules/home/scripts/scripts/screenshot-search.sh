#!/usr/bin/env bash
# screenshot-search — Alfred's "ss" trick, ported to fuzzel.
#
# Fuzzy-pick a screenshot (newest first, each row carrying its own thumbnail),
# then choose an action: copy the image to the clipboard, open it, reveal its
# folder, or delete it. Lets you re-use a recent screenshot without hunting
# through a file manager — paste it straight into a chat/issue. Bound to
# SUPER+SHIFT+S. Screenshots live where the Print-key binds drop them.
set -euo pipefail

dir="${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
font="JetBrainsMono Nerd Font:size=10"

if [[ "$(uname)" == Darwin ]]; then
  # macOS: where the system drops ⌘⇧4 shots (defaults), else the same folder.
  if [ -z "${SCREENSHOT_DIR:-}" ]; then
    loc=$(defaults read com.apple.screencapture location 2>/dev/null || true)
    [ -n "$loc" ] && dir="${loc/#\~/$HOME}"
  fi
  [ -d "$dir" ] || { notify-send "screenshot-search" "No screenshot dir: $dir"; exit 1; }
  # Newest first (BSD stat), NUL-delimited so odd names survive.
  mapfile -d '' -t files < <(
    find "$dir" -maxdepth 1 -type f \
      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) -print0 \
      | xargs -0 /usr/bin/stat -f '%m%t%N%z' | sort -z -rn -k1,1 | cut -z -f2-
  )
  [ "${#files[@]}" -gt 0 ] || { notify-send "screenshot-search" "No screenshots in $dir"; exit 0; }
  # choose has no thumbnail protocol; names carry the timestamp anyway.
  pick=$(for f in "${files[@]}"; do basename "$f"; done | choose -n 18 -w 60 -p 'screenshot ') || exit 0
  [ -n "$pick" ] || exit 0
  file="$dir/$pick"
  [ -f "$file" ] || { notify-send "screenshot-search" "File is gone: $file"; exit 1; }
  action=$(printf 'Copy to clipboard\nOpen\nOpen folder\nDelete' | choose -n 4 -w 40 -p "$pick → ") || exit 0
  case "$action" in
    "Copy to clipboard")
      case "$file" in
        *.png | *.PNG) /usr/bin/osascript -e 'on run argv' -e 'set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)' -e 'end run' -- "$file" ;;
        *) /usr/bin/osascript -e 'on run argv' -e 'set the clipboard to (POSIX file (item 1 of argv))' -e 'end run' -- "$file" ;;
      esac
      notify-send "screenshot-search" "Copied to clipboard: $pick"
      ;;
    "Open") open "$file" ;;
    "Open folder") open -R "$file" ;;
    "Delete") rm -f -- "$file"; notify-send "screenshot-search" "Deleted: $pick" ;;
  esac
  exit 0
fi

[ -d "$dir" ] || { notify-send -u critical "screenshot-search" "No screenshot dir: $dir"; exit 1; }

# Newest first. NUL-delimited throughout so spaces/newlines in names can't
# split a record. find prints "<mtime>\t<path>"; sort -rn on the mtime; cut
# keeps the path.
mapfile -d '' -t files < <(
  find "$dir" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
    -printf '%T@\t%p\0' | sort -z -rn -k1,1 | cut -z -f2-
)

[ "${#files[@]}" -gt 0 ] || { notify-send "screenshot-search" "No screenshots in $dir"; exit 0; }

# fuzzel dmenu icon protocol: "<label>\0icon\x1f<icon-path>". Passing the image
# itself as the icon gives a thumbnail next to each filename.
pick=$(
  for f in "${files[@]}"; do
    printf '%s\0icon\x1f%s\n' "$(basename "$f")" "$f"
  done | fuzzel --dmenu --prompt 'screenshot ' --font "$font" --lines 18 --width 60
) || exit 0
[ -n "$pick" ] || exit 0

file="$dir/$pick"
[ -f "$file" ] || { notify-send -u critical "screenshot-search" "File is gone: $file"; exit 1; }

action=$(printf 'Copy to clipboard\nOpen\nOpen folder\nDelete' \
  | fuzzel --dmenu --prompt "$pick → " --font "$font" --lines 4 --width 40) || exit 0

case "$action" in
  "Copy to clipboard")
    wl-copy --type "$(file -b --mime-type "$file")" <"$file"
    notify-send -i "$file" "screenshot-search" "Copied to clipboard: $pick"
    ;;
  "Open")        setsid -f swayimg "$file" >/dev/null 2>&1 ;;
  "Open folder") setsid -f xdg-open "$dir"  >/dev/null 2>&1 ;;
  "Delete")      rm -f -- "$file"; notify-send "screenshot-search" "Deleted: $pick" ;;
esac
