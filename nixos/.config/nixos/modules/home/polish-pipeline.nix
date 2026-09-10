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
  projectDir = "${config.home.homeDirectory}/Projects/b2-polish-pipeline";
  logDir = "${config.home.homeDirectory}/.local/state/polish-pipeline";

  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  config = lib.mkMerge [
    # systemd.user.tmpfiles has no launchd counterpart; a `home.file` keep-file
    # is what creates the log directory on both platforms.
    (lib.optionalAttrs isLinux {
      systemd.user.tmpfiles.rules = [
        "d ${logDir} 0700 - - - -"
      ];
    })
    (lib.optionalAttrs isDarwin {
      home.file.".local/state/polish-pipeline/.keep".text = "";
    })
    (scheduled {
      name = "polish-pipeline";
      description = "B2 Polish Pipeline: captures → Anki cards (weekly)";
      command = ["${projectDir}/scripts/polish-pipeline-run.sh"];

      after = ["network-online.target"];
      wants = ["network-online.target"];

      onCalendar = "Sat 09:00";
      persistent = true;
      timerUnit = "polish-pipeline.service";
      timerDescription = "Timer for B2 Polish Pipeline (Saturday 09:00)";

      # launchd weekday numbering: 0 = Sunday, so Saturday = 6.
      startCalendarInterval = [
        {
          Weekday = 6;
          Hour = 9;
          Minute = 0;
        }
      ];

      workingDirectory = projectDir;
      linuxPathEntries = [
        "/run/current-system/sw/bin"
        "${config.home.homeDirectory}/.nix-profile/bin"
        "/etc/profiles/per-user/matth/bin"
        "${config.home.homeDirectory}/.local/bin"
      ];
      linuxLogFile = "${logDir}/polish-pipeline.log";
      logFile = "${logDir}/polish-pipeline.log";
      path = [pkgs.bash pkgs.coreutils pkgs.python3];
      darwinPathEntries = [
        "${config.home.homeDirectory}/.nix-profile/bin"
        "/run/current-system/sw/bin"
        "${config.home.homeDirectory}/.local/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ];
    })
  ];
}
