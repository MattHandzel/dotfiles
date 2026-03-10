{
  pkgs,
  inputs,
  username,
  host,
  ...
}: {
  imports = [
    (import ./bootloader.nix)
    (import ./hardware.nix)
    (import ./faster-whisper-server.nix)
    (import ./network.nix)
    (import ./program.nix)
    (import ./security.nix)
    (import ./system.nix)
    (import ./user.nix)
    (import ./services-server.nix)
    (import ./virtualization-server.nix)
    (import ./second-brain-search.nix)
    (import ./text-to-speech-service.nix)
    # Canary is intentionally not imported here; Faster Whisper is the default STT service.
    (import ./nginx.nix)
    (import ./firefly-iii.nix)
    (import ./freshrss.nix)
  ];

  virtualisation.docker.enable = true;
}
