# boox-sync: every 5 min, mirror the BOOX tablet's handwritten notes (its .ksync store, sent to the Mac
# by Syncthing whenever the tablet is on Wi-Fi) into the vault: a PDF per note plus a Markdown file,
# under ~/Obsidian/Main/capture/raw_capture/boox_notes/. Only new or changed notes are drawn.
# Once a note has been left alone for 15 min, claude -p turns its handwriting into Summary / Notes /
# Transcription in that Markdown file (Matt, 2026-11-16: "whenever I write a note ... it automatically
# gets synchronized to my laptop and then also automatically gets processed into a coherent
# document"; this replaces the 2026-10-07 no-AI rule). Drop --transcribe to turn processing off.
#
# Stdlib Python, referenced by its vault path, so edits take effect on the next tick without a
# rebuild. Code: ~/Obsidian/Main/scripts/boox/boox_sync.py. Doc: areas/second-brain/boox-sync.md
{
  config,
  pkgs,
  ...
}: {
  launchd.agents.boox-sync = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${config.home.homeDirectory}/Obsidian/Main/scripts/boox/boox_sync.py" "sync" "--transcribe" "--settle" "15"];
      StartInterval = 300;
      RunAtLoad = true;
      ProcessType = "Background";
      Nice = 10;
      # osascript for notices; claude (~/.local/bin) for processing.
      EnvironmentVariables = {
        PATH = "${config.home.homeDirectory}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/usr/bin:/bin:/usr/sbin:/sbin";
        HOME = config.home.homeDirectory;
      };
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/boox-sync.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/boox-sync.log";
    };
  };
}
