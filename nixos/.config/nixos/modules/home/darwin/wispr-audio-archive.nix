# wispr-audio-archive: every hour, copy Wispr Flow's audio into ~/.local/share/wispr-audio/ before Wispr deletes it.
# Wispr keeps meeting audio (meetings/<id>/upload.ogg) and dictation audio (WAV blobs in flow.sqlite History) for
# only ~14 days (measured 2026-11-09). Meetings are copied as-is (Opus) with their transcripts; dictations are
# transcoded to 24 kb/s Opus. Idempotent (index.jsonl), reads flow.sqlite read-only. Matt, 2026-11-09 (MAT-2054):
# "does wispr flow record and store the audio locally? if not, do so".
# The script is referenced by its vault path, so edits apply on the next tick without a rebuild.
# Code: ~/Obsidian/Main/scripts/wispr-audio/. Doc: areas/second-brain/wispr-audio-archive.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
in {
  launchd.agents.wispr-audio-archive = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${home}/Obsidian/Main/scripts/wispr-audio/wispr_audio_archive.py" "run"];
      StartInterval = 3600;
      RunAtLoad = true;
      # Not Background: Background throttling left a pass at 0.3 s CPU after 2 min on 2026-11-09 (same as shared-notes).
      ProcessType = "Standard";
      Nice = 10;
      EnvironmentVariables.PATH = "${pkgs.ffmpeg}/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin:/bin";
      StandardOutPath = "${home}/.local/state/wispr-audio/launchd.log";
      StandardErrorPath = "${home}/.local/state/wispr-audio/launchd.log";
    };
  };
}
