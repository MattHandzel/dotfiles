{ pkgs, config, ... }:

{
  systemd.user.paths."transcribe-captures" = {
    Unit = {
      Description = "Monitor audio recordings folder for new files";
    };
    Path = {
      DirectoryNotEmpty = "/home/matth/notes/capture/raw_capture/audio_recordings";
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
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      ExecStart = "/home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/transcribe_captures.sh";
      # Ensure it doesn't run multiple instances simultaneously
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
    };
  };
}
