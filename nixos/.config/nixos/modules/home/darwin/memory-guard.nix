# memory-guard: every 10 s, if memory pressure is critical or swap is about to
# run out, end the biggest non-app batch process (never an .app, never kitty /
# claude / tmux) so macOS does not start pausing Dayflow, Beeper and friends.
# See memory-guard.sh for the incident and the victim rules.
{
  config,
  pkgs,
  ...
}: {
  launchd.agents.memory-guard = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" "${./memory-guard.sh}"];
      StartInterval = 10;
      RunAtLoad = true;
      # Launchd would otherwise throttle a 10 s job that exits fast.
      ThrottleInterval = 10;
      ProcessType = "Interactive"; # must still get CPU when the machine is thrashing
      EnvironmentVariables.PATH = "${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${config.home.homeDirectory}/.local/state/memory-guard.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/memory-guard.log";
    };
  };
}
