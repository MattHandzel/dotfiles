# meeting-live: Claude live during a meeting. An always-on local server (127.0.0.1:47620) that tails the Wispr
# Flow recording in progress (~/Library/Application Support/Wispr Flow/meetings/<id>/live.ndjson, ~7 s behind
# speech), scans it with Haiku every ~45 s for requests addressed to Claude, things worth looking up, questions
# aimed at Matt, to-dos and commitments, runs the lookups in one read-only Sonnet session per meeting, and shows
# the results as cards in a web panel (Raycast "Meeting Live", a compact Chrome app window). Cluely's buttons too:
# Assist, Ask (± screenshot), Recap, Follow-ups. Matt, 2026-11-01, from inside a meeting: "constantly searching
# the transcript and identifying if there's something that I want you to do or look up, and then proactively do
# that … make this a web app and then allow me to open it in Raycast."
#
# KeepAlive like wispr-clipboard-sync: it lists the meetings folder every 3 s (cheap) and reads flow.sqlite
# read-only only to confirm a row; it never watches the 1 GB DB. The script is referenced by its vault path, so
# edits take effect on the next restart (launchctl kickstart -k gui/$UID/org.nix-community.home.meeting-live).
# Code: ~/Obsidian/Main/scripts/meeting-live/meeting_live.py. Doc: areas/second-brain/meeting-live.md. MAT-2016.
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
in {
  launchd.agents.meeting-live = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${home}/Obsidian/Main/scripts/meeting-live/meeting_live.py" "serve"];
      RunAtLoad = true;
      KeepAlive = true;
      # Standard, not Background: it runs `claude -p` (see meeting-listener.nix on why a Background clamp hurts).
      ProcessType = "Standard";
      # claude (~/.local/bin), plus the profiles for rg/fd/uv/brain-search the answer session's tools call.
      EnvironmentVariables.PATH = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${home}/.local/state/meeting-live/launchd.log";
      StandardErrorPath = "${home}/.local/state/meeting-live/launchd.log";
    };
  };
}
