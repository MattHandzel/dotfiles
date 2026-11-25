# Meeting commands: `meet` on PATH, and the three-way meeting-title sync every 5 minutes.
#
# Matt, 2026-10-28: a "Meet Prep" Raycast command that finds an upcoming meeting
# and opens its Google Doc (filling the prep when it's empty), a "New Meeting"
# command that puts a meeting on the calendar now, makes its note + Doc, starts
# the Wispr Flow notetaker, opens the Doc and the note in the notetaker neovim,
# and a three-way sync "between google docs, nvim / markdown / and my calendar,
# so if i change the name of the google doc, it changes the name on the calendar".
#
# The CLI is ~/Obsidian/Main/scripts/meetings/meet. `new` and `sync` talk to the
# Calendar API, so the wrapper below runs it on a python that has the Google
# client libraries (the same set meeting-note-docs.nix and wispr-calendar-link.nix
# use); Raycast calls `meet`. The script is referenced by its vault path, so edits
# take effect without a rebuild. Doc: areas/second-brain/meeting-commands.md
{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  isDarwin = host == "mac";

  script = "${config.home.homeDirectory}/Obsidian/Main/scripts/meetings/meet";

  googlePython = pkgs.python3.withPackages (ps:
    with ps; [
      google-auth
      google-auth-oauthlib
      google-api-python-client
    ]);

  meet = pkgs.writeShellScriptBin "meet" ''
    export PATH="$HOME/.local/bin:/etc/profiles/per-user/matth/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
    exec ${googlePython}/bin/python3 ${script} "$@"
  '';

  # gdoc-sync is the home-manager package from packages.nix (a callPackage, not a
  # pkgs attribute), so the agent finds it through the per-user profile.
  run = pkgs.writeShellScript "meeting-title-sync-run" ''
    export PATH="/etc/profiles/per-user/matth/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"
    export GDOC_SYNC_BIN=/etc/profiles/per-user/matth/bin/gdoc-sync
    exec ${googlePython}/bin/python3 ${script} sync
  '';

  inherit (import ../lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  config = lib.mkMerge [
    {home.packages = [meet];}
    (scheduled {
      name = "meeting-title-sync";
      description = "Three-way meeting title sync: calendar event, Google Doc, vault note";
      command = ["${run}"];

      # :02, :07, ...: clear of meeting-note-docs (:10/:40), wispr-meeting-sync
      # (:05/15) and wispr-calendar-link (:08/15) so two jobs never edit one note.
      onCalendar = "*:2/5";
      persistent = true;
      everySeconds = 300;

      # gdoc-sync (Doc title read and rename) and osascript (the conflict
      # notification) come from the PATH the run script exports.
      path = [googlePython pkgs.coreutils];
      logFile = "%h/.local/state/meeting-title-sync.log";

      serviceExtra = {
        TimeoutStartSec = "5m";
        NoNewPrivileges = "yes";
      };
    })
  ];
}
