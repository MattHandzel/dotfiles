# prompt-guide: keep Matt's Claude instructions (CLAUDE.md, memory index, subagents, skills, commands) in line with
# Anthropic's current prompting guidance.
#
#   prompt-guide  04:40 daily: fetch Anthropic's prompting pages (the general best-practices page, the newest
#                 "Prompting Claude <model>" page per family, the Claude Code memory / best-practices / skills /
#                 subagents pages, the models overview). When a new model shows up in the docs, when a page changed
#                 and the last audit is 7+ days old, or every 14 days, audit the instruction files against them
#                 (headless Claude, no tools): wording-only edits are applied, the rest wait as yes/no items in the
#                 AI tips radar's list (Raycast "AI Tips" / "What's New", the built-for-you email at 06:20).
#
# Matt, 2026-11-11: "a service that looks at the best prompting guidelines for Claude, Fable, etc. ... every single
# week or two, or whenever there's a new model that's released ... I say yes or no to them if it's not obvious".
# The script is referenced by its vault path, so edits apply on the next run. Doc: areas/second-brain/prompt-guide.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  script = "${home}/Obsidian/Main/scripts/prompt-guide/prompt-guide";
  # claude (model calls) in ~/.local/bin
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/prompt-guide/launchd.log";
in {
  launchd.agents.prompt-guide = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" script "tick"];
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 40;
        }
      ];
      Nice = 5;
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
