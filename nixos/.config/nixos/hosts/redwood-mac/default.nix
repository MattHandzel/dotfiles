# redwood-mac — the Redwood-issued MacBook (set up 2026-11-23).
#
# Same hands, none of the personal brain: modules/darwin/work.nix gives it
# Matt's system defaults and the Home Manager work profile, and nothing that
# reads the vault, a secret or a personal account. Redwood's device management
# owns the hostname, updates and screen lock, so this host does not set them.
#
# Build here to test:  nix build .#darwinConfigurations.redwood-mac.system
# Switch there:        darwin-rebuild switch --flake .#redwood-mac
{username, ...}: {
  imports = [../../modules/darwin/work.nix];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = 6;
  system.primaryUser = username;

  # Determinate Nix owns the daemon and /etc/nix/nix.conf, as on matts-mac.
  nix.enable = false;
}
