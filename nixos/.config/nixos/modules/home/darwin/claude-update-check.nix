# claude-update-check: every 30 min, if `claude --version` changed since the last check, run the vault's
# after-update smoke test (scripts/agent-tests/scenarios/after-update.sh: CLAUDE.md loads,
# git-destructive-guard blocks, skills/agents listed, every hook fires once) and ntfy Matt if the new
# version broke his setup. Claude Code self-updates outside the flake (see homebrew.nix), so this is
# the check that a silent update didn't switch off his hooks. From the AI tips radar (tip:9f8c650f,
# 2026-10-28). The script is referenced by its vault path, so edits apply on the next run.
# Doc: areas/second-brain/agent-enforcement-and-testing.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  check = "${home}/Obsidian/Main/scripts/agent-tests/after-update-check.sh";
  # claude in ~/.local/bin; jq, git, openssl from the user profile; timeout from coreutils
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/claude-update-check/launchd.log";
in {
  launchd.agents.claude-update-check = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" check];
      StartInterval = 1800;
      RunAtLoad = true;
      Nice = 5;
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
