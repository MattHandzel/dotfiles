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
    # Linux only. On the Mac `uv sync` cannot install the project: morfeusz2
    # (the Polish lemmatizer) ships wheels for manylinux x86_64 and win_amd64
    # only, so the launchd agent could only ever exit 1 (bug
    # err-polish-pipeline-20261019-200819). The card pipeline is parked anyway
    # (projects/B2-polish/B2-polish.md). To run it on the Mac again, get a
    # morfeusz2 build for macOS arm64 first, then drop this guard.
    (lib.optionalAttrs isLinux (scheduled {
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
    }))
  ];
}
