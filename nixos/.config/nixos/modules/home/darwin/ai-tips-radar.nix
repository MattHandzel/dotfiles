# ai-tips-radar: read every AI-tips newsletter, blog, changelog and skill repo Matt follows, and once a week offer
# the few things worth adding to his systems (Raycast "AI Tips", Raycast "What's New", the built-for-you email).
#
#   ai-tips-radar  05:30 daily: fetch new posts from areas/ai-tips-radar/sources.json into
#                  ~/.local/share/ai-tips-radar/radar.db; on Sundays (or when the last digest is 7+ days old) triage
#                  (Haiku), extract tips against his systems inventory (Sonnet), rank (Opus) and write
#                  areas/ai-tips-radar/digests/<week>.md. Runs before built-for-you-nightly (06:20), which emails it.
#
# Matt, 2026-10-21: "something that runs once a week ... identifies what is useful or what would be useful for me to
# include in my systems, and then allows me to very easily add those things". The script is referenced by its vault
# path, so edits apply on the next run. Doc: areas/second-brain/ai-tips-radar.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  radar = "${home}/Obsidian/Main/scripts/ai-tips-radar/radar";
  # claude (model calls) in ~/.local/bin, gh for skill repos
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/ai-tips-radar/launchd.log";
in {
  launchd.agents.ai-tips-radar = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" radar "tick"];
      StartCalendarInterval = [
        {
          Hour = 5;
          Minute = 30;
        }
      ];
      Nice = 5;
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
