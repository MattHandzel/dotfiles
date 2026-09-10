# matts-mac — the Apple-silicon MacBook.
#
# Counterpart to hosts/laptop. Everything platform-neutral lives in
# modules/home (shared with the NixOS hosts through modules/home/default.nix);
# everything macOS-specific lives in modules/darwin.
{
  lib,
  username,
  ...
}: {
  imports = [../../modules/darwin];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "matts-mac";
  networking.computerName = "matts-mac";

  # nix-darwin's state version, NOT a nixpkgs release. 6 is current; bumping it
  # changes migration behaviour, so it stays pinned like a NixOS stateVersion.
  system.stateVersion = 6;

  # Required by nix-darwin for every user-scoped `system.defaults` and for
  # activation to know whose `defaults write` to run.
  system.primaryUser = username;

  # Determinate Nix owns the daemon and /etc/nix/nix.conf. If nix-darwin also
  # managed it, every switch would fight the installer over that file and the
  # first `darwin-rebuild` fails with "Unexpected files in /etc". Extra
  # substituters go in /etc/nix/nix.custom.conf instead.
  #
  # NOTE: with nix.enable = false, do NOT set ids.gids.nixbld — nix-darwin only
  # needs it when it is managing the build group itself.
  nix.enable = false;
}
