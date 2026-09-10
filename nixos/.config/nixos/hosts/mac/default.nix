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

  # MIGRATION OVERRIDE — Matt's call to lift, not a lane's.
  #
  # nix-homebrew refuses to adopt the Homebrew that Track A already installed:
  #   "An existing /opt/homebrew/Library/Homebrew is in the way"
  # and offers `nix-homebrew.autoMigrate = true`, which DELETES the existing
  # installation (keeping the Cellar/Caskroom) and replaces it with the
  # nix-managed checkout.
  #
  # Every cask on this machine — Zen, Slack, Superhuman, Obsidian, Karabiner,
  # the whole Track A set — came from that installation. Deleting and rebuilding
  # it unattended, overnight, with no one able to answer a dialog, is not a
  # trade worth making to gain declarative brew on night one. Everything else in
  # this configuration activates fine without it.
  #
  # To adopt Homebrew later: drop these two lines, set
  # `nix-homebrew.autoMigrate = true`, and re-switch while watching it. Until
  # then the cask/brew lists in modules/darwin/homebrew.nix are the declared
  # truth but are not applied; `cleanup = "none"` there keeps the first
  # managed run from deleting anything.
  nix-homebrew.enable = lib.mkForce false;
  homebrew.enable = lib.mkForce false;
}
