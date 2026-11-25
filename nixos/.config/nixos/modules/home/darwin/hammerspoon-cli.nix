# The `hs` CLI that every `hs -c …` caller runs (error-collector, meeting-listener, the delegate
# engine, Oops, ~/.hammerspoon helpers, Claude sessions), rebuilt with the fix for the abort/hang
# when a command fails: pkgs/hammerspoon-cli (bug listener err-hs-20261019-200819, 2026-11-12).
#
# Hammerspoon.app itself is installed by hand (not a cask), and its stock CLI was linked at
# /opt/homebrew/bin/hs, which scripts call by absolute path. This puts the fixed build in the
# profile (ahead of /opt/homebrew/bin on PATH) and repoints that link at the profile's copy.
# Undo: delete this import; `ln -sfn /Applications/Hammerspoon.app/Contents/Frameworks/hs/hs /opt/homebrew/bin/hs`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  hammerspoon-cli = pkgs.callPackage ../../../pkgs/hammerspoon-cli/default.nix {};
in {
  home.packages = [hammerspoon-cli];

  home.activation.hammerspoonCliLink = lib.hm.dag.entryAfter ["writeBoundary"] ''
    link=/opt/homebrew/bin/hs
    if [ -d /opt/homebrew/bin ] && { [ -L "$link" ] || [ ! -e "$link" ]; }; then
      run ln -sfn "${config.home.profileDirectory}/bin/hs" "$link"
    fi
  '';
}
