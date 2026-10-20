# macOS twins of three automations that are SYSTEM services on the NixOS laptop
# (modules/core/{calendar-agenda,disk-space-alert,gmail-automation}.nix). The
# Mac only imports modules/darwin, so those never had a darwin form; until now
# they existed here only as hand-written, unloaded com.matth.* plists pointing at
# ~/.local/bin/*-run wrappers (the overnight migration lane's stopgap). This is
# the flake-owned version: same scripts, same cadence, launchd agents.
{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  isDarwin = host == "mac";
  inherit (import ../lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
  home = config.home.homeDirectory;

  googlePython = pkgs.python3.withPackages (ps:
    with ps; [
      google-auth
      google-auth-oauthlib
      google-api-python-client
    ]);

  # Subscribed calendars that are NOT Matt's commitments. The read-only token
  # sees every calendar in his sidebar, so someone else's personal calendar can
  # win the sketchybar "now" slot (2026-09-20: "dust hair" from
  # nataliahandzel1@gmail.com, whose 18 class events a week were also filling
  # the agenda). Matched case-insensitively against id / summary /
  # summaryOverride by FOCUS_AGENDA_EXCLUDE in resolver/agenda.py.
  agendaExcludeCalendars = [
    "nataliahandzel1@gmail.com" # Natalia Handzel — Matt's sister
  ];

  # The only calendars the agenda reads (FOCUS_AGENDA_INCLUDE, same matching).
  # An exclude list kept losing to new subscriptions: 2026-09-22 "Mox Events"
  # (a venue feed) held the "now" slot with a 3-day coworking event. Keep in
  # sync with the icalBuddy fallback in sketchybar/plugins/calendar.sh.
  agendaIncludeCalendars = [
    "handzelmatthew@gmail.com"
    "Generator Extension Calendar Core"
    "Generator Extension Calendar Unofficial/Social"
    "Life Scheduler"
    "The Mil"
    "Swapcard calendar"
  ];

  # READ-ONLY: walks every calendar the read-only gcal token can see and writes
  # a merged agenda to ~/.local/state/focus/agenda.json. Exit 2 = missing token
  # (the consumer renders "stale", so it is not a failure).
  calendarAgendaRun = pkgs.writeShellScript "calendar-agenda-run" ''
    agenda="${home}/Projects/system-wide-focus/resolver/agenda.py"
    [ -f "$agenda" ] || { echo "calendar-agenda: $agenda not found." >&2; exit 2; }
    export FOCUS_AGENDA_EXCLUDE=${lib.escapeShellArg (lib.concatStringsSep "," agendaExcludeCalendars)}
    export FOCUS_AGENDA_INCLUDE=${lib.escapeShellArg (lib.concatStringsSep "," agendaIncludeCalendars)}
    exec ${googlePython}/bin/python3 "$agenda"
  '';

  # !! MUTATES GMAIL (moves labels as it turns labelled mail into Taskwarrior
  # tasks + snoozes). Kept out of the active agent set until Matt opts in: set
  # `gmailAutomationEnabled = true` below. The overnight lane left the hand-made
  # plist unloaded for the same reason.
  gmailAutomationEnabled = false;
  gmailAutomationRun = pkgs.writeShellScript "gmail-automation-run" ''
    export PATH="${pkgs.taskwarrior3}/bin:${pkgs.coreutils}/bin:$PATH"
    poller="${home}/Projects/gmail-automation/poller.py"
    [ -f "$poller" ] || { echo "gmail-automation: $poller not found." >&2; exit 2; }
    exec ${googlePython}/bin/python3 "$poller"
  '';
in {
  config = lib.mkMerge [
    (scheduled {
      name = "calendar-agenda";
      description = "Calendar agenda writer — now/next (read-only gcal)";
      command = ["${calendarAgendaRun}"];
      everySeconds = 300; # OnCalendar *:0/5 on the laptop
      path = [pkgs.coreutils];
      logFile = "%h/.local/state/calendar-agenda.log";
    })

    (scheduled {
      name = "disk-space-alert";
      description = "Check free space on the APFS data volume, ntfy on threshold crossing";
      command = ["${pkgs.bash}/bin/bash" "${./disk-space-alert-mac.sh}"];
      everySeconds = 900; # OnUnitActiveSec 15min on the laptop
      runAtLoad = false; # the laptop waits OnBootSec 5min; no burst on wake either
      path = [pkgs.curl pkgs.coreutils pkgs.gawk];
      logFile = "%h/.local/state/disk-space-alert.log";
    })

    (lib.mkIf gmailAutomationEnabled (scheduled {
      name = "gmail-automation";
      description = "Gmail label -> Taskwarrior + snooze poller";
      command = ["${gmailAutomationRun}"];
      everySeconds = 300;
      path = [pkgs.coreutils];
      logFile = "%h/.local/state/gmail-automation.log";
    }))
  ];
}
