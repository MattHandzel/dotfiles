# claude-work-sync: every 15 minutes, rebuild the private repo MattHandzel/claude-work-config from the
# work-safe part of Matt's Claude Code setup (skills.txt, agents.txt, ~/.claude/CLAUDE.md minus the
# personal-only sections) and his Redwood notes (context.txt), scan it with gitleaks, and push if it changed.
# The Redwood laptop pulls it (redwood-mac's claude-config-sync, modules/home/work.nix). Matt, 2026-11-24: "I
# want my claude code experience on my work laptop to be SEAMLESS and the same (same skills, context when i'm
# doing anything work related)". Editing the three lists changes what travels on the next tick.
# Code: ~/Obsidian/Main/scripts/claude-work-sync/. Doc: areas/second-brain/claude-work-sync.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
in {
  launchd.agents.claude-work-sync = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.bash}/bin/bash" "${home}/Obsidian/Main/scripts/claude-work-sync/claude-work-sync"];
      StartInterval = 900;
      RunAtLoad = true;
      ProcessType = "Background";
      StandardOutPath = "${home}/.local/state/claude-work-sync.log";
      StandardErrorPath = "${home}/.local/state/claude-work-sync.err.log";
    };
  };
}
