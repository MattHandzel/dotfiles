# voice-metrics: the weekly measurement of every AI draft against what Matt sent (the voice loop's metric).
#
#   voice-metrics  Sunday 05:00 (after retro-sweep at 04:15): scripts/voice-metrics/weekly.sh
#                  -> voice-metrics weekly: collect pairs (Triage edits, Gmail drafts in Claude Code transcripts
#                     matched to sent mail in the lifelog store, beeper_draft.py calls, capture/draft-*.md),
#                     deterministic metrics, Haiku labels (edit classes, the synonym signal, cut-sentence
#                     functions), the hindsight findability probe for content edits, and the weekly report in
#                     resources/voice-calibration-runs/metrics-<date>.md (numbers only; texts stay in
#                     ~/.local/state/voice-metrics/)
#                  -> a Linear card with the report (or a line in agent/pending-tasks.md when Linear refuses),
#                     error-collector on failure
#
# Matt, 2026-10-29: "lets go for it. you can work comprehensively." Doc: areas/second-brain/voice-metrics.md
{
  config,
  pkgs,
  lib,
  ...
}: let
  home = config.home.homeDirectory;
  weekly = "${home}/Obsidian/Main/scripts/voice-metrics/weekly.sh";
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/voice-metrics/launchd.log";
in {
  home.activation.voiceMetricsLogDir = lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
    run mkdir -p "${home}/.local/state/voice-metrics"
    run chmod 700 "${home}/.local/state/voice-metrics"
  '';

  launchd.agents.voice-metrics = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" weekly];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 5;
          Minute = 0;
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
