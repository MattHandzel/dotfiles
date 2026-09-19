# Everything I download -> my phone.
#
# New files landing in ~/Downloads are linked into ~/ShareComputer/downloads,
# which Syncthing (default.nix) ships to the Pixel 9a. The folder is the same
# "share computer" folder the phone captures come back through; a .stignore
# negation for /downloads is what makes it sync, since that folder is a
# whitelist (`*` at the bottom) and NOT negating a path means silent no-op.
#
# HARDLINKS, not copies: ~/Downloads and ~/ShareComputer are both on
# /System/Volumes/Data, so the link costs no extra bytes on a disk that is
# already 83% full. Syncthing reads a hardlink as an ordinary file. Pruning the
# link later leaves the original in ~/Downloads untouched (refcount), which is
# what makes the retention sweep safe.
#
# Deliberately NOT back-filling the 11 GB / 509-item backlog already sitting in
# ~/Downloads: the phone has ~21 GB free and most of that backlog is installers,
# .part files and old decks. The first run seeds the state file with whatever is
# already there and syncs nothing; only things downloaded afterwards travel.
# To send an existing file, drop it in ~/ShareComputer/downloads by hand.
{
  pkgs,
  lib,
  ...
}: let
  src = "$HOME/Downloads";
  dst = "$HOME/ShareComputer/downloads";
  state = "$HOME/.local/state/downloads-to-phone/seen";

  # Files over this get a notification: the phone is the constrained side and
  # its deletions sit in /sdcard/.trash-storage without freeing space, so a
  # surprise 2 GB arrival is worth saying out loud. It is NOT a cap -- "share
  # everything I download" means everything.
  loudBytes = "524288000"; # 500 MB

  retentionDays = "30";

  # launchd hands an agent a bare PATH (/usr/bin:/bin:/usr/sbin:/sbin), where
  # `stat` is BSD stat and `stat -c` is a hard error. Pin the GNU tools.
  gnuTools = [pkgs.coreutils pkgs.findutils pkgs.gnugrep];

  sync = pkgs.writeShellApplication {
    name = "downloads-to-phone-sync";
    runtimeInputs = gnuTools;
    text = ''
      src="${src}"
      dst="${dst}"
      state="${state}"

      mkdir -p "$dst" "$(dirname "$state")"

      # A TCC tripwire, not a workaround. macOS protects ~/Downloads from some
      # launchd agents, and the denial is silent in the worst way: `find` lists
      # nothing and exits 0, while `test -d` still returns TRUE -- so a blocked
      # agent looks perfectly healthy and ships nothing, forever.
      #
      # Measured 2026-09-16 on this machine: an agent whose program is a plain
      # `#!/bin/bash` script IS denied ("Operation not permitted"), while this
      # script -- run through the nix bash in its shebang -- reads all 462 files
      # fine. That difference is macOS's responsible-process attribution and is
      # not something to rely on. If a future macOS tightens it, this probe
      # turns a silent no-op into a log line plus a notification naming the
      # exact fix: grant Full Disk Access to the stable wrapper path below
      # (which is why the plist must NOT point at a rotating /nix/store path).
      #
      # Keep stderr, discard stdout: the refusal only shows up on stderr.
      probe=$(/bin/ls "$src" 2>&1 >/dev/null) || true
      if printf '%s' "''${probe:-}" | grep -q 'Operation not permitted'; then
        echo "$(date -u +%FT%TZ) BLOCKED: no permission to read $src (macOS TCC)." >&2
        echo "$(date -u +%FT%TZ) Grant Full Disk Access to $HOME/.local/bin/downloads-to-phone-sync" >&2
        stamp="$(dirname "$state")/tcc-warned"
        # Notify once a day, not every 120 s.
        if [ ! -f "$stamp" ] || [ "$(( $(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0) ))" -gt 86400 ]; then
          touch "$stamp"
          /usr/bin/osascript -e 'display notification "Downloads sync is blocked: grant Full Disk Access to downloads-to-phone-sync" with title "Downloads -> Pixel 9a"' </dev/null || true
        fi
        exit 0
      fi

      [ -d "$src" ] || exit 0

      now=$(date +%s)

      # First run: record what is already in Downloads and ship none of it.
      seeded=0
      if [ ! -f "$state" ]; then
        : > "$state"
        seeded=1
      fi

      # Load the state ONCE into a hash. The obvious `grep -qxF "$name"
      # "$state"` per file is O(n^2) and forks ~460 greps every run, which under
      # this agent's Background/Nice throttling took ~40 s per pass on a 120 s
      # timer -- a third of the duty cycle spent re-reading the same file.
      declare -A seen=()
      while IFS= read -r line; do
        [ -n "$line" ] && seen["$line"]=1
      done < "$state"

      while IFS= read -r -d ''' path; do
        name=$(basename "$path")

        # Partial downloads. The browser renames these on completion, so the
        # finished file shows up as a fresh name on a later run.
        case "$name" in
          .*) continue ;;
          *.part | *.partial | *.crdownload | *.download | *.opdownload) continue ;;
          *.tmp | *.temp | *.!ut | *.aria2) continue ;;
        esac

        if [ "$seeded" = 1 ]; then
          printf '%s\n' "$name" >> "$state"
          continue
        fi

        # Already sent.
        if [ -n "''${seen[$name]:-}" ]; then
          continue
        fi

        # Still being written: let the next run take it.
        mtime=$(stat -c %Y "$path" 2>/dev/null || echo 0)
        if [ $((now - mtime)) -lt 15 ]; then
          continue
        fi

        size=$(stat -c %s "$path" 2>/dev/null || echo 0)

        # Hardlink; fall back to a copy if that ever fails (different volume,
        # permissions). Either way the original in ~/Downloads is untouched.
        if ln "$path" "$dst/$name" 2>/dev/null || cp -p "$path" "$dst/$name" 2>/dev/null; then
          printf '%s\n' "$name" >> "$state"
          seen["$name"]=1
          echo "$(date -u +%FT%TZ) sent $name ($size bytes)"
          if [ "$size" -gt ${loudBytes} ]; then
            mb=$((size / 1048576))
            /usr/bin/osascript -e "display notification \"$name (''${mb} MB) is syncing to your phone\" with title \"Downloads -> Pixel 9a\"" </dev/null || true
          fi
        else
          echo "$(date -u +%FT%TZ) FAILED to link $name" >&2
        fi
      done < <(find "$src" -maxdepth 1 -type f -print0)

      if [ "$seeded" = 1 ]; then
        echo "$(date -u +%FT%TZ) seeded state with $(wc -l < "$state" | tr -d ' ') existing files; syncing only new downloads from here"
      fi
    '';
  };

  # Retention. Removes the LINK in ShareComputer/downloads, never the original
  # in ~/Downloads. The delete propagates to the phone (send-receive), which is
  # the whole point -- it is how the phone gets its space back.
  prune = pkgs.writeShellApplication {
    name = "downloads-to-phone-prune";
    runtimeInputs = gnuTools;
    text = ''
      dst="${dst}"
      [ -d "$dst" ] || exit 0
      while IFS= read -r -d ''' path; do
        echo "$(date -u +%FT%TZ) pruning $(basename "$path")"
        rm -f "$path" || true
      done < <(find "$dst" -maxdepth 1 -type f -mtime +${retentionDays} -print0)
    '';
  };
  wrapper = "/Users/matth/.local/bin/downloads-to-phone-sync";
in {
  # A Full Disk Access grant is pinned to the executable's PATH, and a
  # /nix/store path changes on every rebuild -- granting the store path would
  # silently un-grant itself the next time this module is touched. So the
  # launchd agent runs a REAL FILE at a stable path that just execs the current
  # store build. Matt grants FDA to this one path, once, and it survives every
  # rebuild. Must be a real file, not a store symlink, for the same reason the
  # .stignore is (System Settings resolves and rejects store symlinks).
  home.activation.downloadsToPhoneWrapper = lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
    run mkdir -p "$HOME/.local/bin"
    run rm -f "${wrapper}"
    run install -m 755 ${pkgs.writeShellScript "downloads-to-phone-wrapper" ''
      exec ${sync}/bin/downloads-to-phone-sync "$@"
    ''} "${wrapper}"
  '';

  launchd.agents.downloads-to-phone = {
    enable = true;
    config = {
      ProgramArguments = [wrapper];
      # Fires the moment anything lands in Downloads...
      WatchPaths = ["/Users/matth/Downloads"];
      # ...plus a sweep, because WatchPaths misses whatever arrived while the
      # agent was unloaded, and because a partial download completing is a
      # rename the watch may fire on too early.
      RunAtLoad = true;
      StartInterval = 120;
      ProcessType = "Background";
      Nice = 10;
      StandardOutPath = "/Users/matth/Library/Logs/downloads-to-phone.log";
      StandardErrorPath = "/Users/matth/Library/Logs/downloads-to-phone.log";
    };
  };

  launchd.agents.downloads-to-phone-prune = {
    enable = true;
    config = {
      ProgramArguments = ["${prune}/bin/downloads-to-phone-prune"];
      RunAtLoad = false;
      StartInterval = 86400;
      ProcessType = "Background";
      Nice = 15;
      StandardOutPath = "/Users/matth/Library/Logs/downloads-to-phone.log";
      StandardErrorPath = "/Users/matth/Library/Logs/downloads-to-phone.log";
    };
  };
}
