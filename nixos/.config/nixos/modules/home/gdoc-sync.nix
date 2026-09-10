# Periodic two-way reconcile of every linked markdown ↔ Google Doc pair.
#
# A timer rather than `gdoc-sync watch --all`: watch polls every 15s, and with
# ~50 linked files that is thousands of Drive requests an hour for documents
# that change a few times a week. `sync --all` does the same safe three-way
# merge, just on a cadence that matches how fast the docs actually move.
#
# Files imported from a tabbed doc are marked pull-only in the state file, so
# this never pushes them back and never flattens their tabs.
{
  config,
  host,
  inputs,
  lib,
  pkgs,
  ...
}: let
  # Platform test from the `host` specialArg, not from `pkgs` — see the
  # comment at the top of lib/scheduled.nix for why.
  isDarwin = host == "mac";
  isLinux = !isDarwin;
  # The same derivation packages.nix puts on PATH — callPackage with identical
  # arguments yields the identical store path, so this does not build twice.
  gdoc-sync = pkgs.callPackage ../../pkgs/gdoc-sync/default.nix {
    src = inputs.gdoc-sync-src;
  };

  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  config = scheduled {
    name = "gdoc-sync";
    description = "Reconcile linked Markdown files with their Google Docs";
    command = ["${gdoc-sync}/bin/gdoc-sync" "sync" "--all"];

    after = ["network-online.target"];
    wants = ["network-online.target"];

    # Calendar rather than OnBootSec/OnUnitActiveSec: those are monotonic, and
    # a user-manager timer combining them scheduled the first run and then
    # reported NextElapseUSecMonotonic=infinity — it fired once and never
    # again. `Persistent` is also only honoured for calendar timers, and it is
    # what makes a laptop that was asleep at :15 run the reconcile on wake
    # instead of silently skipping to the next quarter hour.
    onCalendar = "*:0/15";
    persistent = true;
    # Docs edited during a meeting should not all land at the same instant.
    randomizedDelaySec = "2m";
    timerDescription = "Periodic Google Docs reconcile";

    # launchd has no OnCalendar-with-repeat; a plain 15-minute interval is the
    # same cadence. A missed interval fires when the Mac wakes, which is what
    # Persistent buys on Linux.
    everySeconds = 900;
    path = [gdoc-sync pkgs.coreutils];
    logFile = "%h/.local/state/gdoc-sync.log";

    serviceExtra = {
      # `sync --all` exits 2 when a file is genuinely conflicted. That is not a
      # crash — it is a decision waiting for Matt — but leaving the unit in a
      # failed state is exactly how it stays visible in `systemctl --user
      # --failed` instead of scrolling past in the journal.
      #
      # The OAuth consent screen is still in Testing, so the refresh token dies
      # about weekly and every run fails until `gdoc-sync auth` is run by hand
      # (MAT-1200). Same reasoning: it should be loud.
      TimeoutStartSec = "10m";

      ProtectSystem = "yes";
      NoNewPrivileges = "yes";
    };
  };
}
