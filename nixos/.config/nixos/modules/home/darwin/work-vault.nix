# ~/Obsidian/Work on both Macs: notes tagged `classification: AL1` sync through the
# private repo MattHandzel/work-vault; everything else stays on the Mac it was
# written on. Imported by ./default.nix (matts-mac) and ../work.nix (redwood-mac).
# Script and rules: ../scripts/scripts/work-vault-sync.sh. Doc: the vault's
# areas/second-brain/work-vault.md.
{
  pkgs,
  lib,
  config,
  ...
}: let
  work = config.my.work or false;
  sync = pkgs.writeShellScriptBin "work-vault-sync" ''
    export PATH=${lib.makeBinPath (with pkgs; [git rsync gitleaks openssh coreutils findutils gawk gnused])}:${config.home.profileDirectory}/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
    ${lib.optionalString work ''
      # The laptop pushes over HTTPS with gh's credential helper (~/.gitconfig).
      export WORK_VAULT_REMOTE="''${WORK_VAULT_REMOTE:-https://github.com/MattHandzel/work-vault.git}"
    ''}
    exec ${pkgs.bash}/bin/bash ${../scripts/scripts/work-vault-sync.sh} "$@"
  '';
in {
  home.packages = [sync];
  launchd.agents.work-vault-sync = {
    enable = true;
    config = {
      ProgramArguments = ["${sync}/bin/work-vault-sync"];
      StartInterval = 300;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/.local/state/work-vault-sync.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/work-vault-sync.log";
    };
  };
}
