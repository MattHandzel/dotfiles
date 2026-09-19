# Phone captures -> vault. The macOS twin of KMS-rebuild/android/systemd/
# (kms-ingest.path + .timer, kms-tags-export.timer) from the NixOS laptop.
#
# The phone's KMS Capture app writes JSON envelopes into ShareComputer/kms-inbox,
# Syncthing (default.nix) lands them in ~/ShareComputer/kms-inbox, and
# `kms ingest` renders each into ~/Obsidian/Main/capture/raw_capture/<id>.md,
# deleting the envelope only after the note exists (the delete syncs back to the
# phone). `kms tags --export` publishes the vault's tag vocabulary for the
# phone's autocomplete.
#
# `kms` is the editable venv in ~/Projects/KMS-rebuild/.venv-darwin, not a nix
# package: the project's flake is x86_64-linux + GTK only.
{pkgs, ...}: let
  kms = "$HOME/Projects/KMS-rebuild/.venv-darwin/bin/kms";
  inbox = "$HOME/ShareComputer/kms-inbox";

  ingest = pkgs.writeShellApplication {
    name = "kms-ingest-run";
    text = ''
      if [ ! -x "${kms}" ]; then
        echo "$(date -u +%FT%TZ) kms not found at ${kms}; skipping" >&2
        exit 0
      fi
      rc=0
      "${kms}" ingest || rc=$?
      # Exit 1 = an envelope was quarantined (malformed). It is kept in
      # kms-inbox/quarantine/, but nobody reads this log, so say it out loud.
      if [ "$rc" -ne 0 ]; then
        /usr/bin/osascript -e "display notification \"kms ingest exited $rc - see ~/Library/Logs/kms-ingest.log\" with title \"KMS phone capture\"" || true
      fi
      exit 0
    '';
  };

  tagsExport = pkgs.writeShellApplication {
    name = "kms-tags-export-run";
    text = ''
      [ -x "${kms}" ] || exit 0
      [ -d "${inbox}" ] || exit 0
      # tags.txt, NOT .json: ingest drains *.json from this directory.
      "${kms}" tags --export "${inbox}/tags.txt"
    '';
  };
in {
  launchd.agents.kms-ingest = {
    enable = true;
    config = {
      ProgramArguments = ["${ingest}/bin/kms-ingest-run"];
      # Fires when Syncthing changes the inbox directory (the .path unit)...
      WatchPaths = ["/Users/matth/ShareComputer/kms-inbox"];
      # ...plus a sweep for anything that landed while the agent was not loaded
      # (the .timer backstop). Ingest is idempotent, so overlaps are safe.
      RunAtLoad = true;
      StartInterval = 300;
      ProcessType = "Background";
      Nice = 10;
      StandardOutPath = "/Users/matth/Library/Logs/kms-ingest.log";
      StandardErrorPath = "/Users/matth/Library/Logs/kms-ingest.log";
    };
  };

  launchd.agents.kms-tags-export = {
    enable = true;
    config = {
      ProgramArguments = ["${tagsExport}/bin/kms-tags-export-run"];
      RunAtLoad = true;
      StartInterval = 3600;
      ProcessType = "Background";
      Nice = 15;
      StandardOutPath = "/Users/matth/Library/Logs/kms-tags-export.log";
      StandardErrorPath = "/Users/matth/Library/Logs/kms-tags-export.log";
    };
  };
}
