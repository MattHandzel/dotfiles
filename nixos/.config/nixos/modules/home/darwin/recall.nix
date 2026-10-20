# recall: be reminded of the right past note when a situation comes up.
#
#   recall-tick   hourly: Haiku tags new or changed notes with "useful when <situation>" cues (store at
#                 ~/.local/share/recall/recall.db, notes are never edited), then reads the calendar ~36 h ahead,
#                 picks the events that start a new situation (a trip, a conference, a first meeting) and emails
#                 a recall brief for each one once (07:00-22:00 only). Briefs are saved to
#                 ~/Obsidian/Main/areas/recall/briefs/.
#
# Matt, 2026-10-19: "whenever i go to a future eag or a future conference, or anything that this information would
# be useful for me to have, i would be reminded of this ... ideally this is something like an email."
# The script is referenced by its vault path, so edits apply on the next tick without a rebuild.
# Code: ~/Obsidian/Main/scripts/recall/recall. Doc: areas/second-brain/recall.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  # uv runs the script (it declares numpy inline), claude for the model calls, rg, icalBuddy for the calendar
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/recall/launchd.log";
in {
  launchd.agents.recall-tick = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.uv}/bin/uv" "run" "--quiet" "--script" "${home}/Obsidian/Main/scripts/recall/recall" "tick"];
      StartInterval = 3600;
      RunAtLoad = false;
      ProcessType = "Background";
      Nice = 10;
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
