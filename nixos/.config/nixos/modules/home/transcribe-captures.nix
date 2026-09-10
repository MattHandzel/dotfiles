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
  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
  home = config.home.homeDirectory;
in {
  config = scheduled {
    name = "transcribe-captures";
    description = "Transcribe audio recordings to text";
    command = ["${home}/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/transcribe_captures.sh"];

    after = ["network.target"];

    watchPaths = [
      "${home}/notes/capture/raw_capture/audio_recordings"
      "${home}/Obsidian/Main/capture/raw_capture/media"
      "${home}/Obsidian/Main/archive/capture/raw_capture"
    ];
    pathsDescription = "Monitor audio recordings for new files";

    path = with pkgs; [bash coreutils unzip nix git];
    logFile = "%h/.local/state/transcribe-captures.log";

    unitExtra = {
      X-Restart-Triggers = [];
      RefuseManualStart = true;
      RefuseManualStop = true;
      X-Switch-To-Configuration = "no";
    };
    serviceExtra = {
      Environment = "PATH=${with pkgs; lib.makeBinPath [bash coreutils unzip nix git]}";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      # Ensure it doesn't run multiple instances simultaneously
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
    };
    launchdExtra = {
      Nice = 10;
      LowPriorityIO = true;
    };
  };
}
