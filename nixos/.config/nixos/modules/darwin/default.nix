# Aggregator for the macOS half, mirroring modules/core/default.nix on NixOS.
{...}: {
  imports = [
    ./system-defaults.nix
    ./homebrew.nix
    ./user.nix
    ./sops.nix
    # ./kanata.nix  # disabled 2026-09-10: Matt does not use kanata on the Mac.
    ./packages.nix
    ./open-with-nvim.nix
    ./dia-policy.nix # Dia auto-installs Matt's extensions (managed-preferences policy)
    ./chrome-policy.nix # Chrome auto-installs Bitwarden (passkeys in the chromium-app windows)
  ];
}
