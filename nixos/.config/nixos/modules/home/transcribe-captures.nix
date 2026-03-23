{ pkgs, config, ... }:

{
  systemd.user.paths."transcribe-captures" = {
    Unit = {
      Description = "Monitor audio recordings for new files";
    };
    Path = {
      PathChanged = [
        "/home/matth/notes/capture/raw_capture/audio_recordings"
        "/home/matth/Obsidian/Main/capture/raw_capture/media"
        "/home/matth/Obsidian/Main/archive/capture/raw_capture"
      ];
      Unit = "transcribe-captures.service";
    };
    Install = {
      WantedBy = [ "paths.target" ];
    };
  };

  systemd.user.services."transcribe-captures" = {
    Unit = {
      Description = "Transcribe audio recordings to text";
      After = [ "network.target" ];
      X-Restart-Triggers = [ ];
      RefuseManualStart = true;
      RefuseManualStop = true;
      X-Switch-To-Configuration = "no";
    };
    Service = {
      Type = "oneshot";
      Environment = "PATH=${with pkgs; lib.makeBinPath [ bash coreutils unzip nix git ]}";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      ExecStart = "/home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/transcribe_captures.sh";
      # Ensure it doesn't run multiple instances simultaneously
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
    };
  };
}
