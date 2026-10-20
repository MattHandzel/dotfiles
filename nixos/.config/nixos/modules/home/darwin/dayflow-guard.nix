# dayflow-guard: keep Dayflow's screenshot interval at 1 s (Matt, 2026-10-06),
# and notify when Dayflow isn't saving a frame about every second while he is
# at the Mac. Runs every 5 min and whenever Dayflow's preferences change. See
# dayflow-guard.sh for the incident and the checks.
{
  config,
  pkgs,
  ...
}: {
  launchd.agents.dayflow-guard = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" "${./dayflow-guard.sh}"];
      StartInterval = 300;
      RunAtLoad = true;
      WatchPaths = ["${config.home.homeDirectory}/Library/Preferences/teleportlabs.com.Dayflow.plist"];
      EnvironmentVariables.PATH = "${pkgs.coreutils}/bin:${pkgs.curl}/bin:${pkgs.gawk}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${config.home.homeDirectory}/.local/state/dayflow-guard.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/dayflow-guard.log";
    };
  };
}
