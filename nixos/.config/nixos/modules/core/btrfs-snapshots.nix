{ config, lib, pkgs, ... }:

# Hourly btrfs snapshots of /home, with simple retention.
#
# Background: On 2026-05-05, ~1.9 GB of irreplaceable personal media was destroyed
# when `git filter-repo` rewrote local history. The files only existed locally
# (push to GitHub had been failing), and Syncthing versioning was disabled at the
# time, so the deletion propagated to the server with no preservation.
#
# Filesystem-level snapshots survive ANY Syncthing- or git-level mistake because
# they're outside both systems. CoW snapshots are nearly free until churn occurs.
#
# Storage notes:
# - /home is its own btrfs partition (subvolid=5, top-level)
# - /home/.snapshots/ is a subvolume created manually for this purpose; snapshots
#   live there and are skipped when other things snapshot /home (no recursion)
# - Retention: keep the most recent 24 `auto-*` snapshots (~24 hours hourly)
# - At ~96% disk usage, longer retention risks ENOSPC; expand once cleaned up
#
# To recover a deleted file:
#   ls /home/.snapshots/                 # pick a snapshot from before the deletion
#   cp /home/.snapshots/auto-<ts>/<path> /home/<path>
#
# To enable: add `(import ./btrfs-snapshots.nix)` to modules/core/default.nix
# imports list, then run scripts/nixos-safe-rebuild.sh.

{
  systemd.services.btrfs-home-snapshot = {
    description = "Take btrfs snapshot of /home with retention";
    path = [ pkgs.btrfs-progs pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      # The script runs as root; btrfs operations require it.
    };
    script = ''
      set -euo pipefail

      SNAP_DIR=/home/.snapshots
      KEEP=24

      if [ ! -d "$SNAP_DIR" ]; then
        echo "ERROR: $SNAP_DIR does not exist. Create it once with:" >&2
        echo "  sudo btrfs subvolume create $SNAP_DIR" >&2
        exit 1
      fi

      TS=$(date -u +%Y-%m-%d-T%H%M%SZ)
      DEST="$SNAP_DIR/auto-$TS"

      btrfs subvolume snapshot -r /home "$DEST"
      echo "Created snapshot: $DEST"

      # Retention: keep the latest $KEEP `auto-*` snapshots, delete older ones.
      mapfile -t old < <(ls -1 "$SNAP_DIR" | grep '^auto-' | sort | head -n "-$KEEP" || true)
      for s in "''${old[@]:-}"; do
        [ -z "$s" ] && continue
        btrfs subvolume delete "$SNAP_DIR/$s"
        echo "Deleted old snapshot: $s"
      done
    '';
  };

  systemd.timers.btrfs-home-snapshot = {
    description = "Hourly btrfs snapshot of /home";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;        # catch up after suspend / downtime
      RandomizedDelaySec = "5m"; # avoid hitting :00 exactly
    };
  };
}
