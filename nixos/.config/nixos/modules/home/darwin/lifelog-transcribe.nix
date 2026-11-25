# lifelog-transcribe: every 10 min, send the phone recordings phone_pull.py copied to
# ~/.local/share/lifelog/phone-recordings/ (Easy Voice Recorder talks, and since 2026-10-29 every phone,
# WhatsApp and Telegram call from Tasker "Call Rec") to the server's Faster Whisper (matts-server:47770),
# and write <file>.json/.txt next to each. `lifelog ingest` (source `recordings`) puts the text in the
# store. Matt, 2026-10-29: "everything was transcribed automatically".
#
# At most 2 files a run, calls first; a server that's down is retried every 6 h. Audio and text stay
# outside the vault. The script is referenced by its vault path, so edits apply on the next tick without
# a rebuild. Code: ~/Obsidian/Main/scripts/lifelog/transcribe.py. Doc: areas/second-brain/lifelog.md.
{
  config,
  pkgs,
  ...
}: {
  launchd.agents.lifelog-transcribe = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${config.home.homeDirectory}/Obsidian/Main/scripts/lifelog/transcribe.py"];
      StartInterval = 600;
      RunAtLoad = true;
      Nice = 10;
      # ffprobe from the user profile (the same ffmpeg lifelog uses for frames).
      EnvironmentVariables.PATH = "/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:${pkgs.coreutils}/bin:/usr/bin:/bin";
      StandardOutPath = "${config.home.homeDirectory}/.local/state/lifelog/transcribe-launchd.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/lifelog/transcribe-launchd.log";
    };
  };
}
