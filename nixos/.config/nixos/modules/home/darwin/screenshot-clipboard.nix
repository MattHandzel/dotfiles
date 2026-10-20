# Every capture from the macOS Screenshot app (⌘⇧3/⌘⇧4/⌘⇧5, or Raycast →
# "Screenshot") also lands on the clipboard, the way the Print key does
# (AeroSpace f13/shift-f13 → kbshot: PNG in ~/Pictures/Screenshots AND on the
# clipboard). Matt, Oops 20261007-190042: "if I take a screenshot … use the Mac
# screenshot application, it automatically copies it to my clipboard".
#
# macOS can only save to a file OR the clipboard (com.apple.screencapture
# target), and the file has to stay: screenshot-search and quick-capture read
# ~/Pictures/Screenshots. So target stays "file" (system-defaults.nix) and this
# agent watches the folder and copies the newest macOS-named capture
# ("Screenshot 2026-10-07 at 19.00.34.png"). kbshot's own files
# ("2026-10-07-07h00m34s.png") are already on the clipboard and do not match.
# Only a capture under 30 s old is copied, and only once (the last copied path
# is kept in ~/.local/state/screenshot-clipboard/last), so a later event in the
# folder (xattrs, a delete, an OCR .txt) never overwrites what Matt copied since.
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  copy = pkgs.writeShellApplication {
    name = "screenshot-clipboard";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      dir="$HOME/Pictures/Screenshots"
      state="$HOME/.local/state/screenshot-clipboard"; mkdir -p "$state"
      shopt -s nullglob
      fresh_capture() {
        newest="" newest_m=0
        for f in "$dir"/Screenshot\ *.png; do
          m=$(stat -c %Y "$f" 2>/dev/null || echo 0)
          if [ "$m" -gt "$newest_m" ]; then newest="$f" newest_m="$m"; fi
        done
        [ -n "$newest" ] && [ $(($(date +%s) - newest_m)) -le 30 ] &&
          [ "$newest" != "$(cat "$state/last" 2>/dev/null || true)" ]
      }
      # The watch usually fires on screencapture's hidden ".Screenshot … .png"
      # temp file, ~20 ms before the real name appears (measured 2026-10-07),
      # and launchd's throttle would then hold the real event back: look again
      # for up to 1.5 s instead.
      found=0
      for _ in $(seq 15); do
        if fresh_capture; then found=1; break; fi
        sleep 0.1
      done
      [ "$found" = 1 ] || exit 0
      # The watch can fire while the PNG is still being written: wait (≤3 s)
      # until its size is non-zero and unchanged across 0.1 s.
      prev=-1
      for _ in $(seq 30); do
        size=$(stat -c %s "$newest" 2>/dev/null || echo 0)
        if [ "$size" -gt 0 ] && [ "$size" = "$prev" ]; then break; fi
        prev="$size"; sleep 0.1
      done
      /usr/bin/osascript -e 'on run argv' -e 'set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)' -e 'end run' -- "$newest"
      printf '%s\n' "$newest" > "$state/last"
      echo "$(date '+%F %T') copied $(basename "$newest") ($size bytes)"
    '';
  };
in {
  launchd.agents.screenshot-clipboard = {
    enable = true;
    config = {
      ProgramArguments = ["${copy}/bin/screenshot-clipboard"];
      WatchPaths = ["${home}/Pictures/Screenshots"];
      # launchd's default 10 s throttle would hold back a second screenshot
      # taken right after the first.
      ThrottleInterval = 1;
      ProcessType = "Interactive";
      StandardOutPath = "${home}/.local/state/screenshot-clipboard/launchd.log";
      StandardErrorPath = "${home}/.local/state/screenshot-clipboard/launchd.log";
    };
  };
}
