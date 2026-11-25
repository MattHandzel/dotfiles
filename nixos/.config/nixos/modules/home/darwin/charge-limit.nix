# charge-limit: the battery charge cap, owned by the flake.
#
# The cap is macOS's own Charge Limit
# (System Settings › Battery › Charge Limit, enforced by PowerUIAgent;
# `pmset -g battlimit` shows it). AlDente is installed but is not started at
# login, so its `chargeVal` (modules/darwin/system-defaults.nix) does nothing.
#
# The agent sets the limit at login and at 00:05 every day, so the slider is
# put back at the next run: change the cap here, not in System Settings.
# Matt asked on 2026-10-11 for full charges until Oct 24 (Oops
# 20261011-070711), then on 2026-11-07 for full charges with no end date
# (Oops 20261107-114343): the cap is 100 % = off. Change `want` to re-cap.
#
# Manual: `charge-limit` prints the limit, `charge-limit 90` sets it.
# Log: ~/Library/Logs/charge-limit.log (one line per change).
{
  config,
  pkgs,
  ...
}: let
  charge-limit = pkgs.runCommandCC "charge-limit" {} ''
    mkdir -p $out/bin
    $CC -fobjc-arc -framework Foundation ${./charge-limit.m} -o $out/bin/charge-limit
  '';
  # `date` comes from PATH, not the store, so a shim can test the cutover.
  apply = pkgs.writeShellScript "charge-limit-apply" ''
    want=100
    have=$(${charge-limit}/bin/charge-limit) || exit 1
    if [ "$have" != "$want" ]; then
      ${charge-limit}/bin/charge-limit "$want" >/dev/null || exit 1
      echo "$(date '+%F %T') charge limit $have -> $want %"
    fi
  '';
in {
  home.packages = [charge-limit];

  launchd.agents.charge-limit = {
    enable = true;
    config = {
      ProgramArguments = ["${apply}"];
      RunAtLoad = true;
      StartCalendarInterval = [
        {
          Hour = 0;
          Minute = 5;
        }
      ];
      EnvironmentVariables.PATH = "/usr/bin:/bin";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/charge-limit.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/charge-limit.log";
    };
  };
}
