# gdoc-claude: "@claude ..." in a Google Docs comment -> a headless Claude does it and replies in the thread.
#
#   gdoc-claude  every 60 s: scripts/gdoc-claude/gdoc_claude.py poll
#                -> scans Docs Matt viewed/edited in the last 24 h for new comments by Matt containing @claude,
#                   replies "[Claude] On it.", spawns `gdoc_claude.py work` (claude -p + the gdoc-do-it skill,
#                   locked-down profile scripts/headless/profiles/gdoc-do.settings.json), which edits/suggests in
#                   the Doc and replies with what changed. ntfy push on finish.
#
# Matt, 2026-11-04: "have Claude automatically identify that I have requested something ... and then Claude can do it."
# Doc: areas/second-brain/gdoc-claude.md. Runs on the Mac for now; moving it to matts-server needs the Google token there.
{
  config,
  pkgs,
  lib,
  ...
}: let
  home = config.home.homeDirectory;
  script = "${home}/Obsidian/Main/scripts/gdoc-claude/gdoc_claude.py";
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/gdoc-claude/launchd.log";
in {
  home.activation.gdocClaudeStateDir = lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
    run mkdir -p "${home}/.local/state/gdoc-claude"
    run chmod 700 "${home}/.local/state/gdoc-claude"
  '';

  launchd.agents.gdoc-claude = {
    enable = true;
    config = {
      ProgramArguments = ["/usr/bin/env" "python3" script "poll"];
      StartInterval = 60;
      RunAtLoad = true;
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
