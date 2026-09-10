{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  # Platform test from the `host` specialArg, not from `pkgs` — see the
  # comment at the top of lib/scheduled.nix for why.
  isDarwin = host == "mac";
  isLinux = !isDarwin;
  # Was a hardcoded /home/matth; the Mac's home is /Users/matth.
  scriptsDir = "${config.home.homeDirectory}/Projects/relationship-os-core";
  stateDir = "${config.home.homeDirectory}/.local/state/luck-scheduler";

  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;

  # Everything the luck jobs share: they all run from the vault, all log to
  # their own file under ~/.local/state/luck-scheduler, and all need the same
  # small toolchain on PATH.
  luck = job: let
    # `logName` is this module's own bookkeeping (the log file drops the `luck-`
    # prefix the unit carries), not a `scheduled` argument.
    j = builtins.removeAttrs job ["logName"];
    logPath = "${stateDir}/${job.logName}.log";
  in
    scheduled ({
        after = ["network.target"];
        workingDirectory = "${config.home.homeDirectory}/Obsidian/Main";
        linuxPathEntries = [
          "/run/current-system/sw/bin"
          "${config.home.homeDirectory}/.nix-profile/bin"
          "/etc/profiles/per-user/matth/bin"
        ];
        path = [pkgs.bash pkgs.coreutils pkgs.python3 pkgs.git];
        timerUnit = "${job.name}.service";
      }
      // j
      // {
        linuxLogFile = logPath;
        logFile = logPath;
      });
in {
  config = lib.mkMerge (
    [
      # Ensure log directory exists before services run
      (lib.optionalAttrs isLinux {
        systemd.user.tmpfiles.rules = [
          "d %h/.local/state/luck-scheduler 0700 - - - -"
        ];
      })
      (lib.optionalAttrs isDarwin {
        home.file.".local/state/luck-scheduler/.keep".text = "";
      })
    ]
    ++ map luck [
      {
        name = "luck-m1-refresh";
        logName = "m1-refresh";
        description = "Luck: Weekly M1 relationship refresh (Sunday 19:00)";
        command = ["${scriptsDir}/scheduler.sh" "m1-refresh"];
        onCalendar = "Sun *-*-* 19:00:00";
        persistent = true;
        startCalendarInterval = [
          {
            Weekday = 0;
            Hour = 19;
            Minute = 0;
          }
        ];
      }
      {
        name = "luck-sunday-review";
        logName = "sunday-review";
        description = "Luck: Weekly Sunday review (Sunday 19:30)";
        command = ["${scriptsDir}/scheduler.sh" "sunday-review"];
        onCalendar = "Sun *-*-* 19:30:00";
        persistent = true;
        startCalendarInterval = [
          {
            Weekday = 0;
            Hour = 19;
            Minute = 30;
          }
        ];
      }
      {
        name = "luck-now-update";
        logName = "now-update";
        description = "Luck: Weekly now-update (Sunday 19:45)";
        command = ["${scriptsDir}/scheduler.sh" "now-update"];
        onCalendar = "Sun *-*-* 19:45:00";
        persistent = true;
        startCalendarInterval = [
          {
            Weekday = 0;
            Hour = 19;
            Minute = 45;
          }
        ];
      }
      {
        name = "luck-enrich-weekly";
        logName = "enrich-weekly";
        description = "Luck: Weekly contact enrichment (Tuesday 09:00)";
        command = ["${scriptsDir}/scheduler.sh" "enrich-contact" "auto"];
        onCalendar = "Tue *-*-* 09:00:00";
        persistent = true;
        startCalendarInterval = [
          {
            Weekday = 2;
            Hour = 9;
            Minute = 0;
          }
        ];
      }
      {
        name = "luck-parse-capture-poll";
        logName = "parse-capture-poll";
        description = "Luck: Poll ntfy for relationship/linkedin captures (every 5min)";
        command = ["${scriptsDir}/ntfy-poll.sh"];
        onCalendar = "*:0/5";
        persistent = false;
        everySeconds = 300;
      }
      {
        name = "luck-drafts-watch";
        logName = "drafts-watch";
        description = "Luck: Watch drafts-to-ship for published status (every 5min)";
        command = ["${scriptsDir}/drafts-watch.sh"];
        onCalendar = "*:0/5";
        persistent = false;
        everySeconds = 300;
      }
      {
        name = "luck-relationships-cache-refresh";
        logName = "relationships-cache-refresh";
        description = "Luck: Daily relationship cache refresh (06:00)";
        command = [
          "${pkgs.bash}/bin/bash"
          "-c"
          "${pkgs.python3}/bin/python3 ${scriptsDir}/parser.py && ${pkgs.python3}/bin/python3 ${scriptsDir}/staleness.py && ${pkgs.python3}/bin/python3 ${scriptsDir}/cluster-map.py"
        ];
        onCalendar = "*-*-* 06:00:00";
        persistent = true;
        startCalendarInterval = [
          {
            Hour = 6;
            Minute = 0;
          }
        ];
      }
      {
        name = "luck-m3-quarterly";
        logName = "m3-quarterly";
        description = "Luck: Quarterly M3 blast (first Sunday of quarter 10:00)";
        command = ["${scriptsDir}/scheduler.sh" "m3-quarterly-blast"];
        # First Sunday of each quarter: Jan/Apr/Jul/Oct, day 1-7, Sunday.
        # systemd OnCalendar does not natively support "first Sunday of month" so we
        # use a monthly timer on Sun 1-7 of Jan/Apr/Jul/Oct as the closest approximation.
        # This fires every Sunday in the first week of those months; the skill itself
        # is idempotent so multiple fires in the same week are harmless.
        onCalendar = "Sun *-1,4,7,10-01..07 10:00:00";
        persistent = true;
        timerDescription = "Timer for luck-m3-quarterly";
        # launchd cannot express "first Sunday of the quarter" at all — it has no
        # month field combined with a weekday. Fire EVERY Sunday at 10:00 and let
        # the skill no-op outside the quarter boundary, same idempotence argument.
        startCalendarInterval = [
          {
            Weekday = 0;
            Hour = 10;
            Minute = 0;
          }
        ];
      }
    ]
  );
}
