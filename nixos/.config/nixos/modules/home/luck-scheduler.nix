{
  config,
  lib,
  pkgs,
  ...
}: let
  scriptsDir = "/home/matth/Projects/relationship-os-core";

  mkLuckService = {
    name,
    description,
    execStart,
    extraEnv ? {},
  }: {
    Unit = {
      Description = description;
      After = ["network.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = execStart;
      WorkingDirectory = "${config.home.homeDirectory}/Obsidian/Main";
      Environment =
        ["PATH=/run/current-system/sw/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/matth/bin"]
        ++ lib.mapAttrsToList (k: v: "${k}=${v}") extraEnv;
      StandardOutput = "append:${config.home.homeDirectory}/.local/state/luck-scheduler/${name}.log";
      StandardError = "append:${config.home.homeDirectory}/.local/state/luck-scheduler/${name}.log";
    };
  };

  mkLuckTimer = {
    name,
    description,
    onCalendar,
    persistent ? true,
  }: {
    Unit = {
      Description = "Timer for luck-${name}";
    };
    Timer = {
      OnCalendar = onCalendar;
      Persistent = persistent;
      Unit = "luck-${name}.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
in {
  # Ensure log directory exists before services run
  systemd.user.tmpfiles.rules = [
    "d %h/.local/state/luck-scheduler 0700 - - - -"
  ];

  # ── Services ──────────────────────────────────────────────────────────────

  systemd.user.services.luck-m1-refresh = mkLuckService {
    name = "m1-refresh";
    description = "Luck: Weekly M1 relationship refresh (Sunday 19:00)";
    execStart = "${scriptsDir}/scheduler.sh m1-refresh";
  };

  systemd.user.services.luck-sunday-review = mkLuckService {
    name = "sunday-review";
    description = "Luck: Weekly Sunday review (Sunday 19:30)";
    execStart = "${scriptsDir}/scheduler.sh sunday-review";
  };

  systemd.user.services.luck-now-update = mkLuckService {
    name = "now-update";
    description = "Luck: Weekly now-update (Sunday 19:45)";
    execStart = "${scriptsDir}/scheduler.sh now-update";
  };

  systemd.user.services.luck-enrich-weekly = mkLuckService {
    name = "enrich-weekly";
    description = "Luck: Weekly contact enrichment (Tuesday 09:00)";
    execStart = "${scriptsDir}/scheduler.sh enrich-contact auto";
  };

  systemd.user.services.luck-parse-capture-poll = mkLuckService {
    name = "parse-capture-poll";
    description = "Luck: Poll ntfy for relationship/linkedin captures (every 5min)";
    execStart = "${scriptsDir}/ntfy-poll.sh";
  };

  systemd.user.services.luck-drafts-watch = mkLuckService {
    name = "drafts-watch";
    description = "Luck: Watch drafts-to-ship for published status (every 5min)";
    execStart = "${scriptsDir}/drafts-watch.sh";
  };

  systemd.user.services.luck-relationships-cache-refresh = mkLuckService {
    name = "relationships-cache-refresh";
    description = "Luck: Daily relationship cache refresh (06:00)";
    execStart = "${pkgs.bash}/bin/bash -c '${pkgs.python3}/bin/python3 ${scriptsDir}/parser.py && ${pkgs.python3}/bin/python3 ${scriptsDir}/staleness.py && ${pkgs.python3}/bin/python3 ${scriptsDir}/cluster-map.py'";
  };

  systemd.user.services.luck-m3-quarterly = mkLuckService {
    name = "m3-quarterly";
    description = "Luck: Quarterly M3 blast (first Sunday of quarter 10:00)";
    execStart = "${scriptsDir}/scheduler.sh m3-quarterly-blast";
  };

  # ── Timers ────────────────────────────────────────────────────────────────

  systemd.user.timers.luck-m1-refresh = mkLuckTimer {
    name = "m1-refresh";
    description = "Weekly M1 refresh";
    onCalendar = "Sun *-*-* 19:00:00";
  };

  systemd.user.timers.luck-sunday-review = mkLuckTimer {
    name = "sunday-review";
    description = "Weekly Sunday review";
    onCalendar = "Sun *-*-* 19:30:00";
  };

  systemd.user.timers.luck-now-update = mkLuckTimer {
    name = "now-update";
    description = "Weekly now-update";
    onCalendar = "Sun *-*-* 19:45:00";
  };

  systemd.user.timers.luck-enrich-weekly = mkLuckTimer {
    name = "enrich-weekly";
    description = "Weekly contact enrichment";
    onCalendar = "Tue *-*-* 09:00:00";
  };

  systemd.user.timers.luck-parse-capture-poll = mkLuckTimer {
    name = "parse-capture-poll";
    description = "ntfy poll every 5 minutes";
    onCalendar = "*:0/5";
    persistent = false;
  };

  systemd.user.timers.luck-drafts-watch = mkLuckTimer {
    name = "drafts-watch";
    description = "Drafts watch every 5 minutes";
    onCalendar = "*:0/5";
    persistent = false;
  };

  systemd.user.timers.luck-relationships-cache-refresh = mkLuckTimer {
    name = "relationships-cache-refresh";
    description = "Daily relationship cache refresh";
    onCalendar = "*-*-* 06:00:00";
  };

  # First Sunday of each quarter: Jan/Apr/Jul/Oct, day 1-7, Sunday
  # systemd OnCalendar does not natively support "first Sunday of month" so we
  # use a monthly timer on Sun 1-7 of Jan/Apr/Jul/Oct as the closest approximation.
  # This fires every Sunday in the first week of those months; the skill itself
  # is idempotent so multiple fires in the same week are harmless.
  systemd.user.timers.luck-m3-quarterly = mkLuckTimer {
    name = "m3-quarterly";
    description = "Quarterly M3 blast (first week of Jan/Apr/Jul/Oct, Sunday)";
    onCalendar = "Sun *-1,4,7,10-01..07 10:00:00";
  };
}
