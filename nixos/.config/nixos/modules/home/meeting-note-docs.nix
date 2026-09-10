# Give every upcoming meeting note a shareable Google Doc (MAT-1185, MAT-1813).
#
# The meeting-note generator is split across two machines on purpose:
#
#   matts-server  reads the calendar and writes capture/meetings/*.md  (every 30m)
#   this laptop   gives each of those notes a Google Doc                (here)
#
# The server half needs a calendar token; the Doc half needs gdoc-sync, which
# is installed and authenticated here and NOT there. Rather than copy OAuth
# credentials onto the server, `--docs-only` walks the notes the server already
# wrote and creates the missing Docs. It reads no calendar and needs no Google
# client libraries — plain python3 plus gdoc-sync on PATH.
#
# This unit only CREATES and LINKS. Ongoing reconciliation belongs to the
# `gdoc-sync sync --all` timer in gdoc-sync.nix, which three-way merges every
# linked pair every 15 minutes — that is what pulls notes typed into the Doc
# during a meeting back into the vault.
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
  gdoc-sync = pkgs.callPackage ../../pkgs/gdoc-sync/default.nix {
    src = inputs.gdoc-sync-src;
  };

  script = "${config.home.homeDirectory}/Obsidian/Main/scripts/calendar/meeting_notes.py";

  # The script runs from a literal vault path, so edits to it take effect on the
  # next tick without a rebuild — same convention as the server unit.
  run = pkgs.writeShellScript "meeting-note-docs-run" ''
    export PATH=${gdoc-sync}/bin:${pkgs.pandoc}/bin:$PATH
    exec ${pkgs.python3}/bin/python3 ${script} --docs-only
  '';

  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  config = scheduled {
    name = "meeting-note-docs";
    description = "Create a shareable Google Doc for each upcoming meeting note";
    command = ["${run}"];

    after = ["network-online.target"];
    wants = ["network-online.target"];

    # :10 and :40 — offset from the server's :00/:30 note-writing tick so the two
    # halves are never mid-write on one file, and from gdoc-sync.timer's *:0/15.
    #
    # OnCalendar, NOT the monotonic OnBootSec/OnUnitActiveSec pair: written that
    # way, gdoc-sync.timer fired exactly once and then sat at
    # NextElapseUSecMonotonic=infinity while still reporting enabled + active
    # with a successful last run. Persistent is also only honoured for calendar
    # timers, and it is the whole point here — the laptop is routinely asleep,
    # and a meeting note that appears overnight must get its Doc on wake rather
    # than silently skip the slot.
    onCalendar = "*:10/30";
    persistent = true;
    randomizedDelaySec = "3m";
    timerDescription = "Periodic Google Doc creation for upcoming meeting notes";

    everySeconds = 1800;
    path = [gdoc-sync pkgs.pandoc pkgs.python3 pkgs.coreutils];
    logFile = "%h/.local/state/meeting-note-docs.log";

    serviceExtra = {
      # Each Doc is a pandoc render plus several Drive/Docs calls; a backlog of
      # notes after the laptop has been shut for a few days is the slow case.
      TimeoutStartSec = "15m";
      NoNewPrivileges = "yes";
    };
  };
}
