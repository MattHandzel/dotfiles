{
  pkgs,
  inputs,
  ...
}: {
  # imports = [inputs.whisper-overlay.nixosModules.default];
  # nixpkgs.config.cudaSupport = true; # Optional, for GPU speed
  # services.realtime-stt-server.enable = true;
  # environment.systemPackages = [pkgs.whisper-overlay];
}
