# Give every upcoming meeting note a shareable Google Doc (MAT-1185, MAT-1813).
#
# On Linux the meeting-note generator is split across two machines on purpose:
#
#   matts-server  reads the calendar and writes capture/meetings/*.md  (every 30m)
#   this laptop   gives each of those notes a Google Doc                (here)
#
# On the Mac (host "mac") this unit runs the WHOLE generator — calendar -> note ->
# Doc — because the server that wrote the notes is down (2026-09-24 Oops: no
# note since 2026-09-09). The Mac already has both credentials: the read-only
# calendar token at ~/.config/focus-mode-resolver/token.json (shared with the
# calendar-agenda agent) and gdoc-sync's own. Same 7-day window the server used.
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

  # The full generator reads the calendar, so it needs the Google client libs.
  googlePython = pkgs.python3.withPackages (ps:
    with ps; [
      google-auth
      google-auth-oauthlib
      google-api-python-client
    ]);

  # The script runs from a literal vault path, so edits to it take effect on the
  # next tick without a rebuild — same convention as the server unit.
  run =
    if isDarwin
    then
      # ripgrep: when a rescheduled meeting's note is renamed, the generator
      # points every [[link]] to it at the new name (note_sync.rewrite_backlinks).
      pkgs.writeShellScript "meeting-note-docs-run" ''
        export PATH=${gdoc-sync}/bin:${pkgs.pandoc}/bin:${pkgs.ripgrep}/bin:$PATH
        export MEETING_NOTES_DAYS=7
        exec ${googlePython}/bin/python3 ${script}
      ''
    else
      pkgs.writeShellScript "meeting-note-docs-run" ''
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
    path = [gdoc-sync pkgs.pandoc pkgs.ripgrep pkgs.python3 pkgs.coreutils];
    logFile = "%h/.local/state/meeting-note-docs.log";

    # Background (the scheduled.nix default) is PRI 4 on the E-cores only: on a
    # busy Mac a 10:32 run sat 6 min in dyld init before Python started, and
    # this morning's runs timed out linking the 11:30 meeting's Doc (Oops
    # 20261020-101750). Matt needs the Doc before the meeting.
    launchdExtra.ProcessType = "Standard";

    serviceExtra = {
      # Each Doc is a pandoc render plus several Drive/Docs calls; a backlog of
      # notes after the laptop has been shut for a few days is the slow case.
      TimeoutStartSec = "15m";
      NoNewPrivileges = "yes";
    };
  };
}
