# aerospace-watchdog: every 15 s, confirm the AeroSpace server still answers and
# relaunch it if it does not. See aerospace-watchdog.sh for the two failure
# modes and why nothing else covers them.
{
  config,
  pkgs,
  ...
}: {
  launchd.agents.aerospace-watchdog = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" "${./aerospace-watchdog.sh}"];
      StartInterval = 15;
      RunAtLoad = true;
      ThrottleInterval = 15;
      EnvironmentVariables.PATH =
        # aerospace is the Homebrew cask's binary (see modules/darwin/homebrew.nix);
        # notify-send is the compat shim from compat-shims.nix.
        "${config.home.profileDirectory}/bin:/opt/homebrew/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${config.home.homeDirectory}/.local/state/aerospace-watchdog.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/aerospace-watchdog.log";
    };
  };
}
