{
  config,
  lib,
  ...
}: let
  projectDir = "/home/matth/Projects/b2-polish-pipeline";
  logDir = "${config.home.homeDirectory}/.local/state/polish-pipeline";
in {
  systemd.user.tmpfiles.rules = [
    "d ${logDir} 0700 - - - -"
  ];

  systemd.user.services.polish-pipeline = {
    Unit = {
      Description = "B2 Polish Pipeline: captures → Anki cards (weekly)";
      After = ["network-online.target"];
      Wants = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${projectDir}/scripts/polish-pipeline-run.sh";
      WorkingDirectory = projectDir;
      Environment = [
        "PATH=/run/current-system/sw/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/matth/bin:${config.home.homeDirectory}/.local/bin"
      ];
      StandardOutput = "append:${logDir}/polish-pipeline.log";
      StandardError = "append:${logDir}/polish-pipeline.log";
    };
  };

  systemd.user.timers.polish-pipeline = {
    Unit = {
      Description = "Timer for B2 Polish Pipeline (Saturday 09:00)";
    };
    Timer = {
      OnCalendar = "Sat 09:00";
      Persistent = true;
      Unit = "polish-pipeline.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}
