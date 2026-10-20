# built-for-you: tell Matt what Claude built for him, in the two places he named (Raycast "What's new" and an email).
#
#   built-for-you-nightly  06:20: sweep for builds no session announced (Raycast, skills, agents, problem-log
#                          fixes, Neovim plugins and keys, launchd, AeroSpace, espanso), apply his email replies,
#                          run the use check, rewrite areas/built-for-you/changelog.md, and send the morning email
#                          when there's something to say (it's waiting at the first lid-open, see morning-focus.nix).
#   built-for-you-replies  every 10 min: apply "3 show" / "5 keep" / "5 drop" lines from his replies to that email.
#
# Matt, 2026-10-19: "the surfaces should be "raycast: what's new" and an email". The script is referenced by its vault
# path, so edits apply on the next run without a rebuild. Code: ~/Obsidian/Main/scripts/built-for-you/bfy.
# Doc: areas/second-brain/built-for-you.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  bfy = "${home}/Obsidian/Main/scripts/built-for-you/bfy";
  # claude (Haiku calls) in ~/.local/bin, git and fd for inventory.py, open for `show`, sudo for a drop's switch
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/built-for-you/launchd.log";
in {
  launchd.agents.built-for-you-nightly = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" bfy "nightly"];
      StartCalendarInterval = [
        {
          Hour = 6;
          Minute = 20;
        }
      ];
      # Not ProcessType "Background": on 2026-10-20 a run started in a dark wake sat throttled for 4 hours.
      # bfy also gives up on its own after 30 min (replies: 5 min).
      Nice = 5;
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
  launchd.agents.built-for-you-replies = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" bfy "replies"];
      StartInterval = 600;
      RunAtLoad = false;
      Nice = 5;
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
