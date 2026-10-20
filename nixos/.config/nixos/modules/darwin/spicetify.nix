# Spotify with ads blocked (spicetify + the rxri adblock extension), the Mac
# twin of modules/home/spicetify.nix. Adblock only: no theme, podcasts stay.
#
# A SYSTEM module on purpose, not Home Manager: nix-darwin copies the app into
# /Applications/Nix Apps root-owned and read-only, so Spotify's own updater
# (running as matth) cannot swap in an unpatched build between rebuilds, as it
# did to the Homebrew cask (pinned tap, yet the app had self-updated to
# 1.3.4.258). HM's copyApps makes writable copies. The Spotify cask is gone
# from homebrew.nix: two apps with the same bundle id make `open -a Spotify`
# pick the newer, unpatched one.
{
  inputs,
  pkgs,
  ...
}: let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in {
  imports = [inputs.spicetify-nix.darwinModules.default];

  programs.spicetify = {
    enable = true;
    enabledExtensions = [spicePkgs.extensions.adblock];
  };
}
