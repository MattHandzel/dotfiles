# retro-sweep: the weekly agent error sweep of the self-improvement loop (MAT-61), moved to the Mac.
#
#   retro-sweep  Sunday 04:15: scripts/self-improve/run-analysis-pass.sh
#                -> run-retro-sweep.sh --headless --commit: `claude -p --agent retrospective-analyst` (opus,
#                   read-only tools, --max-budget-usd) mines the week's ~/.claude/projects/-Users-matth-*
#                   transcripts with the most human turns into ~/.claude/self-improve/findings/<id>.json
#                -> file-agent-errors.sh file: dedup into ~/.claude/self-improve/learnings.json, file new
#                   classes on Linear (a refusal such as the free-plan issue cap is logged as
#                   "WARN linear-filing-failed" and kept on the class as filing_error, never a crash)
#                -> file-agent-errors.sh measure: areas/second-brain/agent-error-recurrence.md
#
# Before this, the sweep ran only on the sold NixOS laptop, so learnings.json stopped at 2026-09-17. Matt approved
# the move in the rule-audit proposal of 2026-10-22. launchd runs a missed Sunday slot when the Mac wakes. The
# scripts are referenced by their vault path, so edits apply on the next run.
# Doc: areas/second-brain/agent-self-improvement-system.md
{
  config,
  pkgs,
  lib,
  ...
}: let
  home = config.home.homeDirectory;
  pass = "${home}/Obsidian/Main/scripts/self-improve/run-analysis-pass.sh";
  # claude in ~/.local/bin; jq/fd/rg/GNU coreutils from the nix profiles; error-collector per-user
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/retro-sweep/launchd.log";
in {
  home.activation.retroSweepLogDir = lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
    run mkdir -p "${home}/.local/state/retro-sweep"
  '';

  launchd.agents.retro-sweep = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" pass];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 4;
          Minute = 15;
        }
      ];
      Nice = 5;
      WorkingDirectory = "${home}/Obsidian/Main";
      EnvironmentVariables = {
        PATH = path;
        HOME = home;
      };
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
