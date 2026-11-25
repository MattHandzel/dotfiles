# Every 15 min, commit + push ~/dotfiles changes left untouched for 30 min, once
# both Macs still evaluate and gitleaks is clean, so the Redwood laptop's
# dotfiles-sync gets them (Matt, 2026-11-25, ";scfo ... wasn't synced").
# matts-mac only. Script: ../scripts/scripts/dotfiles-autopush.sh.
{
  pkgs,
  lib,
  config,
  ...
}: let
  push = pkgs.writeShellScriptBin "dotfiles-autopush" ''
    export PATH=${lib.makeBinPath (with pkgs; [git gitleaks openssh coreutils gnused gnugrep])}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin
    exec ${pkgs.bash}/bin/bash ${../scripts/scripts/dotfiles-autopush.sh} "$@"
  '';
in {
  home.packages = [push];
  launchd.agents.dotfiles-autopush = {
    enable = true;
    config = {
      ProgramArguments = ["${push}/bin/dotfiles-autopush"];
      StartInterval = 900;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/.local/state/dotfiles-autopush.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/dotfiles-autopush.log";
    };
  };
}
