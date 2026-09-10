# Aggregator for the macOS half, mirroring modules/core/default.nix on NixOS.
{...}: {
  imports = [
    ./system-defaults.nix
    ./homebrew.nix
    ./user.nix
    ./sops.nix
    ./kanata.nix
    ./packages.nix
  ];
}
