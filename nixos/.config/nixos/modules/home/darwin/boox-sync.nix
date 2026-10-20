# boox-sync: every 30 min, mirror the BOOX (Onyx) cloud's handwritten notes into the vault:
# a PDF per note plus a Markdown file (text boxes as text), under
# ~/Obsidian/Main/capture/raw_capture/boox_notes/. Only new or changed notes are fetched.
# No AI: Matt (2026-10-07) said this agent should not be an AI agent, so it never passes --transcribe.
# Matt, 2026-10-07: "make it so that everything's automatically downloaded from this website into
# my Obsidian vault so that things have access to it."
#
# Stdlib Python, referenced by its vault path, so edits take effect on the next tick without a
# rebuild. Auth is BOOX_TOKEN in the vault .env (`scripts/boox/boox-sync login`); with no token it
# exits quietly, and an expired one posts one notification a day. Code:
# ~/Obsidian/Main/scripts/boox/boox_sync.py. Doc: areas/second-brain/boox-sync.md
{
  config,
  pkgs,
  ...
}: {
  launchd.agents.boox-sync = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${config.home.homeDirectory}/Obsidian/Main/scripts/boox/boox_sync.py" "sync"];
      StartInterval = 1800;
      RunAtLoad = true;
      ProcessType = "Background";
      Nice = 10;
      # osascript for the expired-token notice.
      EnvironmentVariables = {
        PATH = "${config.home.homeDirectory}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        HOME = config.home.homeDirectory;
      };
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/boox-sync.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/boox-sync.log";
    };
  };
}
