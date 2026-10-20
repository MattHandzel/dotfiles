# shared-notes: every 5 minutes, look through the newest messages in the lifelog store (every Gmail and Beeper
# message, filled every 2 min by lifelog-ingest-messages) for meeting notes, transcripts and docs someone sent
# Matt (Granola, Plaud, Gemini notes, Notion, Google Docs, ...). Fetchable ones are stored: meeting notes in
# capture/meetings/transcripts/, other people's docs as private snapshots in ~/.local/share/shared-notes/docs/.
# Each becomes a lifelog event (src "shares") and a line in the sender's person file. Ones Claude can't fetch
# (a login, an unknown service) are proposed in the "Shared with you" block of today's daily note, which the
# shutdown ritual reads. Matt, 2026-10-19: "hernan ... sent me the meeting transcripts ... please store that
# locally and figure out a way so that that happens automatically ... make a generalizable solution".
#
# Reads the store by id cursor, so a pass is ~0.1 s when nothing arrived. The script is referenced by its vault
# path, so edits apply on the next tick without a rebuild.
# Code: ~/Obsidian/Main/scripts/shared-notes/. Doc: areas/second-brain/shared-notes.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
in {
  launchd.agents.shared-notes = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${home}/Obsidian/Main/scripts/shared-notes/shared_notes.py" "scan"];
      StartInterval = 300;
      RunAtLoad = true;
      # Not Background: on 2026-10-19, with eight Claude sessions running, a Background pass sat at 0% CPU for
      # minutes still inside Python's startup. A pass is a fraction of a second, so normal priority costs nothing.
      ProcessType = "Standard";
      Nice = 5;
      # pandoc (Granola notes HTML and uploaded .docx -> Markdown)
      EnvironmentVariables.PATH = "/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${home}/.local/state/shared-notes/launchd.log";
      StandardErrorPath = "${home}/.local/state/shared-notes/launchd.log";
    };
  };
}
