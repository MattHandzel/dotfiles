# matchmaker: what people Matt knows want x opportunities he comes across -> one ready-to-send draft a day in
# Triage's Send-to-several queue. Nothing is sent from here; Matt sends or skips each row.
#
#   matchmaker  08:30, 11:30, 14:30, 17:30 daily: scripts/matchmaker/run.sh -> mm.py run
#               intake   new posts in the Slack opportunity channels, opportunity-like newsletters (lifelog store),
#                        Matt's "opportunity ..." captures -> offers, each with a predicted stale date
#               refresh  new meeting transcripts and new direct messages -> people's wants and offers
#               match    new offers x current wants, new wants x what other people offer (Opus)
#               track    Triage's queue: sent -> give log + person file; replies classed (helped / already saw / no)
#               propose  rules, then checks on the top pair (want re-read in its source, linked page read for the
#                        deadline, lifelog done-check), then one row into Triage (07:00-15:00 only, <= 3 a day ever)
#               ~/.local/share/matchmaker/last-ok.json is written only after a pass with no failed step; a failed
#               step exits 1 (error-collector sees it).
#
# Matt, 2026-11-15: "build all the things that haven't been built". Doc: areas/second-brain/matchmaker-infra.md
{
  config,
  pkgs,
  lib,
  ...
}: let
  home = config.home.homeDirectory;
  run = "${home}/Obsidian/Main/scripts/matchmaker/run.sh";
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/matchmaker/launchd.log";
  at = h: m: {
    Hour = h;
    Minute = m;
  };
in {
  home.activation.matchmakerDirs = lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
    run mkdir -p "${home}/.local/state/matchmaker" "${home}/.local/share/matchmaker"
    run chmod 700 "${home}/.local/state/matchmaker" "${home}/.local/share/matchmaker"
  '';

  launchd.agents.matchmaker = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" run];
      StartCalendarInterval = [(at 8 30) (at 11 30) (at 14 30) (at 17 30)];
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
