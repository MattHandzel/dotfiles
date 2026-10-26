# Tie every Wispr Flow recording to the calendar, both ways, every 15 minutes.
#
# Matt, 2026-10-26: a recording made during a calendar event should be "stuck to
# that meeting", and a recording with nothing on the calendar should become an
# event, so the calendar shows the day as it happened. The script matches each
# finished recording to its event (Wispr's own link first, then time overlap),
# records the match for wispr-meeting-sync.nix (which then links the meeting's
# note and its Google Doc), adds the Wispr link to the description of events
# Matt organizes, and creates an event for recordings nothing covered.
#
# Reads use the meeting-notes generator's read-only calendar token. Writes use a
# separate `calendar.events` token that Matt grants once with
# `wispr_calendar_link.py authorize`; until then the job only matches.
#
# Mac-only for the same reason as wispr-meeting-sync.nix: the Wispr Flow store
# lives under ~/Library. The script is referenced by its literal vault path, so
# edits take effect on the next tick without a rebuild.
{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  isDarwin = host == "mac";

  script = "${config.home.homeDirectory}/Obsidian/Main/scripts/wispr/wispr_calendar_link.py";

  # Same Google client libs as meeting-note-docs.nix.
  googlePython = pkgs.python3.withPackages (ps:
    with ps; [
      google-auth
      google-auth-oauthlib
      google-api-python-client
    ]);

  run = pkgs.writeShellScript "wispr-calendar-link-run" ''
    exec ${googlePython}/bin/python3 ${script}
  '';

  inherit (import ../lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  config = scheduled {
    name = "wispr-calendar-link";
    description = "Tie Wispr Flow recordings to calendar events, and add events for unscheduled ones";
    command = ["${run}"];

    # :08, :23 and so on: after wispr-meeting-sync's :05 tick has mirrored a new
    # recording, and clear of meeting-note-docs' :10/:40.
    onCalendar = "*:8/15";
    persistent = true;
    everySeconds = 900;

    path = [googlePython pkgs.coreutils];
    logFile = "%h/.local/state/wispr-calendar-link.log";

    serviceExtra = {
      TimeoutStartSec = "10m";
      NoNewPrivileges = "yes";
    };
  };
}
