{
  inputs,
  nixpkgs,
  self,
  username,
  host,
  ...
}: let
  desktop-imports = [(import ./home-assistant.nix) (import ./default.desktop.nix)];
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
      (import ./wayland.nix)
      (import ./virtualization.nix)
      (import ./bluetooth.nix)
    ]
    ++ (
      if host == "desktop"
      then desktop-imports
      else []
    );

  services.geoclue2 = {
    enable = true;
    #   providers = {
    #     modem-gps = {
    #       enabled = false;
    #     };
    #     host-ip = {
    #       enabled = true;
    #     };
    #     wifi = {
    #       enabled = true;
    #     };
    #   };
  };
  location.provider = "geoclue2";
}
