# Mirror Wispr Flow's recorded meetings into the vault every 15 minutes.
#
# Wispr Flow keeps each meeting's summary and transcript in its own local store
# (~/Library/Application Support/Wispr Flow: flow.sqlite plus meetings/<id>/*.ndjson)
# and nowhere else on disk, so the notes are readable only inside the app and
# invisible to every other tool in the second brain. This agent copies each one
# into `capture/meetings/transcripts/`, links it from the calendar-generated
# note that shares its Google Calendar event id, and lists the day's meetings in
# that day's daily note.
#
# Mac-only by construction: Wispr Flow is a macOS app and the store lives under
# ~/Library. That is why this sits in darwin/ rather than the shared list, next
# to wispr-clipboard-sync.nix which reads the same DB for dictations.
#
# WHY A POLL AND NOT A WATCH
# --------------------------
# The obvious trigger is a WatchPaths on the meetings folder, but the useful
# write is not the one that creates it. Wispr writes `live.ndjson` while
# recording and only later replaces it with the cleaned-up `refined.ndjson`
# (minutes to hours, after a server round-trip) — and the derived summary lands
# separately again, in the DB. A watch fires on the first of those and produces
# a note built from the worst version. A 15-minute poll re-renders each meeting
# until its inputs stop changing, and the script no-ops when nothing did.
#
# The script is referenced by its literal vault path, so edits to it take effect
# on the next tick without a rebuild — the same convention meeting-note-docs.nix
# uses for its half of the meeting pipeline.
{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  isDarwin = host == "mac";

  script = "${config.home.homeDirectory}/Obsidian/Main/scripts/wispr/wispr_meeting_sync.py";

  run = pkgs.writeShellScript "wispr-meeting-sync-run" ''
    exec ${pkgs.python3}/bin/python3 ${script}
  '';

  inherit (import ../lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  config = scheduled {
    name = "wispr-meeting-sync";
    description = "Mirror Wispr Flow meeting notes and transcripts into the vault";
    command = ["${run}"];

    # :05 and :20 and so on — offset from meeting-note-docs' :10/30 tick so the
    # two halves of the meeting pipeline are never mid-write on one file.
    onCalendar = "*:5/15";
    persistent = true;
    everySeconds = 900;

    # No network, no credentials: everything it reads is on this disk. python3
    # only (sqlite3 is in the stdlib); coreutils is for the log rotation the
    # helper wraps the command in.
    path = [pkgs.python3 pkgs.coreutils];
    logFile = "%h/.local/state/wispr-meeting-sync.log";

    serviceExtra = {
      # A first run with a backlog renders every meeting in the store; steady
      # state is a few seconds.
      TimeoutStartSec = "10m";
      NoNewPrivileges = "yes";
    };
  };
}
