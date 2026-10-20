# systemstatus-guard: every 15 min, measure how long macOS's privacy-indicator
# daemon (systemstatusd) takes per update and notify Matt to reboot once it is
# slow enough to threaten the camera in a call. See systemstatus-guard.sh for
# the 2026-10-06 interview incident and the thresholds.
{
  config,
  pkgs,
  ...
}: {
  launchd.agents.systemstatus-guard = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" "${./systemstatus-guard.sh}"];
      StartInterval = 900;
      RunAtLoad = true;
      EnvironmentVariables.PATH = "${pkgs.coreutils}/bin:${pkgs.curl}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${config.home.homeDirectory}/.local/state/systemstatus-guard.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/systemstatus-guard.log";
    };
  };
}
