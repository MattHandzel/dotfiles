{
  inputs,
  nixpkgs,
  self,
  username,
  host,
  ...
}: let
  desktop-imports = [(import ./default.desktop.nix) (import ./faster-whisper-server.nix)];
in {
  imports =
    [
      (import ./bootloader.nix)
      (import ./hardware.nix)
      (import ./xserver.nix)
      (import ./network.nix)
      (import ./pipewire.nix)
      (import ./program.nix)
      (import ./security.nix)
      (import ./services.nix)
      (import ./system.nix)
      (import ./user.nix)
      (import ./tor.nix)
      (import ./wayland.nix)
      (import ./virtualization.nix)
      (import ./bluetooth.nix)
      (import ./sops.nix)
      (import ./gocryptfs-vault.nix)
      (import ./disk-space-alert.nix)
    ]
    ++ (
      if host == "desktop"
      then desktop-imports
      else []
    );

  services.geoclue2 = {
    enable = true;
  };
  location.provider = "geoclue2";
}
