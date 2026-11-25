# otter-sync: every 30 minutes, pull Matt's Otter.ai conversations (phone recordings, OtterPilot on Zoom/Meet)
# into capture/meetings/transcripts/YYYY-MM-DD-otter-<slug>.md through Otter's official MCP server
# (https://mcp.otter.ai/mcp, OAuth; no password, no browser cookies). Matt, 2026-11-24 (delegate dlg-1d73a0):
# "Do you automatically pull all my meeting notes from Otter.ai? If not, you should do some automation".
# One-time sign-in: python3 ~/Obsidian/Main/scripts/otter/otter_sync.py auth. Until then every pass exits 2, so
# error-collector shows otter-sync as down; that is the reminder.
# Code: ~/Obsidian/Main/scripts/otter/. Doc: areas/second-brain/otter-sync.md
{config, pkgs, ...}: let
  home = config.home.homeDirectory;
in {
  launchd.agents.otter-sync = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${home}/Obsidian/Main/scripts/otter/otter_sync.py" "run"];
      StartInterval = 1800;
      RunAtLoad = true;
      ProcessType = "Standard";
      Nice = 5;
      StandardOutPath = "${home}/.local/state/otter-sync/launchd.log";
      StandardErrorPath = "${home}/.local/state/otter-sync/launchd.log";
    };
  };
}
