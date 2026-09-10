# Vicinae — a native, Wayland-first Raycast clone: hit a hotkey, get a command
# palette (launch apps, run commands/scripts, clipboard history, calculator,
# timers). Chosen over Ulauncher/Albert because it is built for Wayland (no
# XWayland) and its config lives in files, which suits this declarative setup.
#
# It runs as a background server + a toggled window (like Raycast). The server is
# a user service tied to the graphical session; SUPER+D toggles the window (bound
# in hyprland/config.nix).
{
  pkgs,
  config,
  ...
}: let
  # graphical-session.target can be reached before Hyprland has exported
  # WAYLAND_DISPLAY to the systemd user manager. Starting Vicinae in that gap
  # makes Qt fall back to xcb, crash five times in quick succession, and leave
  # SUPER+D inert for the rest of the login. Resolve the live compositor socket
  # here so startup does not depend on that environment-import race.
  vicinaeServer = pkgs.writeShellScript "vicinae-server" ''
    set -eu

    # Everything Vicinae launches — desktop applications and script commands
    # alike — is forked from this process and inherits its environment. A
    # systemd user unit starts with a near-empty PATH (just the unit's own
    # closure), and most desktop entries use a bare "Exec=kitty" rather than an
    # absolute path, so the server's execve fails with "No such file or
    # directory" and the app silently never appears. Same gap breaks script
    # commands whose helpers live in the user profile or ~/.local/bin.
    export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/matth/bin:$HOME/.local/bin:$HOME/.nix-profile/bin:''${PATH:-}"

    runtimeDir="''${XDG_RUNTIME_DIR:-/run/user/$UID}"

    # hyprctl refuses to run without the live instance signature, and the
    # systemd user manager never imports it. Resolve it from the runtime dir so
    # scripts that dispatch through Hyprland work when run from the palette.
    resolveHyprland() {
      if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        return 0
      fi
      for dir in "$runtimeDir"/hypr/*/; do
        [ -S "''${dir}.socket.sock" ] || continue
        dir="''${dir%/}"
        export HYPRLAND_INSTANCE_SIGNATURE="''${dir##*/}"
        return 0
      done
      return 0
    }

    for ((attempt = 0; attempt < 300; attempt++)); do
      if [ -n "''${WAYLAND_DISPLAY:-}" ] &&
        [ -S "$runtimeDir/$WAYLAND_DISPLAY" ]; then
        resolveHyprland
        exec ${pkgs.vicinae}/bin/vicinae server
      fi

      for socket in "$runtimeDir"/wayland-*; do
        [ -S "$socket" ] || continue
        export WAYLAND_DISPLAY="''${socket##*/}"
        resolveHyprland
        exec ${pkgs.vicinae}/bin/vicinae server
      done

      ${pkgs.coreutils}/bin/sleep 0.1
    done

    echo "Vicinae: no Wayland socket appeared in $runtimeDir after 30 seconds" >&2
    exit 1
  '';

  # Normally the server is already running. If it ever failed, make the hotkey
  # repair it and wait until it is actually responsive before toggling the UI.
  vicinaeToggle = pkgs.writeShellScriptBin "vicinae-toggle" ''
    set -u

    if ! ${pkgs.vicinae}/bin/vicinae ping >/dev/null 2>&1; then
      ${pkgs.systemd}/bin/systemctl --user reset-failed vicinae.service
      ${pkgs.systemd}/bin/systemctl --user start vicinae.service

      for ((attempt = 0; attempt < 100; attempt++)); do
        if ${pkgs.vicinae}/bin/vicinae ping >/dev/null 2>&1; then
          exec ${pkgs.vicinae}/bin/vicinae toggle
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      ${pkgs.libnotify}/bin/notify-send \
        -u critical \
        "Vicinae failed to start" \
        "Run: journalctl --user -u vicinae.service"
      exit 1
    fi

    exec ${pkgs.vicinae}/bin/vicinae toggle
  '';

  # Vicinae discovers script commands in ~/.local/share/vicinae/scripts (its
  # default scripts dir — no settings.json registration needed). Each script
  # declares itself via "@vicinae.*" header comments (schemaVersion/title/mode,
  # optional argument1..3 as JSON). Modes: silent/compact = toast after the
  # window closes (right for toggles), fullOutput = result view (searches),
  # terminal = spawn a terminal. PATH is set explicitly because the vicinae
  # server (a systemd user unit) does not inherit the interactive shell PATH.
  # Interpolated into every script below, immediately after its "@vicinae.*"
  # header comments. Besides PATH, it installs an exit trap that writes an
  # AUTOFIX marker to the journal on any nonzero exit — that marker is what
  # claude-autofix.nix's watcher picks up to dispatch a repair. Vicinae swallows
  # a failing script's output, so without this a broken command fails silently.
  #
  # That trap only fires on a nonzero *script* exit, so a wrapper of the shape
  #
  #     some-helper
  #     echo "Done"        # <- resets $? to 0
  #
  # silently discards the helper's failure: the palette shows the success toast
  # and the watcher never sees the marker. Wrappers below therefore run the
  # helper as `helper || exit` so the real status propagates. It is deliberately
  # NOT applied to commands whose helper opens an interactive picker and exits
  # nonzero when the user cancels (keybinds, wallpaper, ocr-screenshot,
  # quick-capture, record-*): there a plain Escape is not a failure, and
  # propagating it would dispatch an autofix run for normal use.
  pathPreamble = ''
    export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/matth/bin:$HOME/.local/bin:$HOME/.nix-profile/bin:$PATH"
    _vicinae_script="$(basename "$0" .sh)"
    trap '_rc=$?; if [ "$_rc" -ne 0 ]; then logger -t autofix "AUTOFIX: vicinae-$_vicinae_script: script exited with status $_rc"; fi' EXIT
  '';

  mkScript = name: body: {
    "vicinae/scripts/${name}.sh" = {
      executable = true;
      text = body;
    };
  };

  scripts =
    # Meeting recorder — the command Matt named explicitly. Toggle: first run
    # starts an audio-only arecord into ~/notes/capture/meetings, second run
    # stops it. Audio-only (no network dependency); transcription can be run
    # later via the existing whisper server tooling.
    mkScript "record-meeting" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Record Meeting (toggle)
      # @vicinae.mode compact
      # @vicinae.argument1 { "type": "text", "placeholder": "meeting name", "optional": true }
      ${pathPreamble}
      DIR="$HOME/notes/capture/meetings"
      PIDFILE="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/meeting-rec.pid"
      NAMEFILE="''${PIDFILE%.pid}.name"
      if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        kill -INT "$(cat "$PIDFILE")"
        rm -f "$PIDFILE"
        notify-send -u normal -i audio-input-microphone "Meeting recording stopped" "$(cat "$NAMEFILE" 2>/dev/null)"
        echo "Stopped: $(cat "$NAMEFILE" 2>/dev/null)"
        rm -f "$NAMEFILE"
        exit 0
      fi
      mkdir -p "$DIR"
      name="''${1:-meeting}"
      safe=$(printf '%s' "$name" | tr -c '[:alnum:]._-' '_')
      out="$DIR/$(date +%Y-%m-%d_%H-%M-%S)_$safe.wav"
      nohup arecord -f cd "$out" >/dev/null 2>&1 &
      echo $! >"$PIDFILE"
      echo "$out" >"$NAMEFILE"
      notify-send -u normal -i audio-input-microphone "Meeting recording started" "$out"
      echo "Recording → $out"
    ''
    // mkScript "white-noise" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Brown Noise (toggle)
      # @vicinae.mode compact
      ${pathPreamble}
      # Brown noise is generated on the fly by mpv's lavfi anoisesrc source — no
      # audio file to store and no network/download dependency. anoisesrc with no
      # duration plays forever; toggle stops it. amplitude/volume kept moderate so
      # it isn't jarring; adjust system volume to taste.
      # The player deliberately lives in its own systemd user unit rather than
      # being backgrounded from here. Vicinae reaps the process group of a script
      # it ran once the script exits — even through setsid/nohup — so a
      # backgrounded mpv is killed the instant the toggle returns (the symptom:
      # "Brown noise on", then silence and no mpv). Handing the process to the
      # user manager puts it in its own cgroup, outside Vicinae's lifecycle.
      if systemctl --user --quiet is-active white-noise.service; then
        systemctl --user stop white-noise.service
        notify-send -u normal -i audio-volume-muted "Brown noise off"
        echo "Brown noise off"
        exit 0
      fi

      # A muted default sink is the other reason this toggle looks "broken": mpv
      # runs, the stream is routed, and nothing is audible. Asking for brown noise
      # is an explicit request to hear something, so unmute — and say so, since
      # the unmute also affects everything else on that sink.
      unmuted=""
      if wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED; then
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 2>/dev/null && unmuted=" (unmuted output)"
      fi

      systemctl --user start white-noise.service 2>/dev/null || true

      # Verify it actually survived startup instead of reporting success blindly.
      sleep 1
      if ! systemctl --user --quiet is-active white-noise.service; then
        notify-send -u critical -i dialog-error "Brown noise failed to start" \
          "$(journalctl --user -u white-noise.service -n 3 --no-pager -o cat 2>/dev/null)"
        echo "Brown noise failed to start — journalctl --user -u white-noise.service"
        exit 1
      fi
      notify-send -u normal -i audio-volume-high "Brown noise on$unmuted"
      echo "Brown noise on$unmuted"
    ''
    // mkScript "toggle-focus-mode" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Toggle Focus Mode
      # @vicinae.mode silent
      ${pathPreamble}
      toggle-focus-mode || exit
      echo "Focus mode toggled"
    ''
    // mkScript "stt-copy" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title STT: Dictate → Clipboard (toggle)
      # @vicinae.mode silent
      ${pathPreamble}
      toggle-stt --copy || exit
      echo "STT (copy) toggled"
    ''
    // mkScript "stt-type" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title STT: Dictate → Type Into Window (toggle)
      # @vicinae.mode silent
      ${pathPreamble}
      toggle-stt --type || exit
      echo "STT (type) toggled"
    ''
    // mkScript "quick-capture" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Quick Capture (text/clip/audio/screenshot)
      # @vicinae.mode silent
      ${pathPreamble}
      quick-capture
      echo "Capture done"
    ''
    // mkScript "take-note" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Take Note
      # @vicinae.mode compact
      # @vicinae.argument1 { "type": "text", "placeholder": "note text" }
      ${pathPreamble}
      take-note "$1" || exit
      echo "Noted: $1"
    ''
    // mkScript "brain-search" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Search Second Brain
      # @vicinae.mode fullOutput
      # @vicinae.argument1 { "type": "text", "placeholder": "query" }
      ${pathPreamble}
      brain-search "$1"
    ''
    // mkScript "lifelog-search" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Lifelog Search
      # @vicinae.mode silent
      ${pathPreamble}
      lifelog-search || exit
      echo "Lifelog opened"
    ''
    # Drafting-velocity session (Chapin: clear 500 words/hour and you outrun the
    # inner critic). One toggle for both directions, because the whole point is
    # that starting to write must not itself become a decision. Once running,
    # any prose buffer you type in joins automatically — no file is ever named.
    # `toggle` prints its own start/stop summary, so there is no trailing echo
    # here that would reset $? and hide a failure from the pathPreamble trap.
    // mkScript "writing-session" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Writing Session: Start/Stop (words/hour)
      # @vicinae.mode compact
      ${pathPreamble}
      writing-session toggle || exit
    ''
    // mkScript "writing-report" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Writing Sessions: Recent Speed
      # @vicinae.mode fullOutput
      ${pathPreamble}
      writing-session report
    ''
    // mkScript "password-type" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Password: Type Into Focused Window
      # @vicinae.mode silent
      ${pathPreamble}
      password-picker || exit
      echo "Password picker done"
    ''
    // mkScript "password-copy" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Password: Copy (auto-clears 45s)
      # @vicinae.mode silent
      ${pathPreamble}
      password-picker copy || exit
      echo "Password copied"
    ''
    // mkScript "ocr-screenshot" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title OCR Screenshot → Clipboard
      # @vicinae.mode silent
      ${pathPreamble}
      ocr-screenshot
      echo "OCR result in clipboard"
    ''
    // mkScript "record-screen" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Record Screen (toggle; run again to stop)
      # @vicinae.mode silent
      ${pathPreamble}
      record screen
      echo "Screen recording toggled"
    ''
    // mkScript "record-area-gif" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Record Area → GIF (toggle)
      # @vicinae.mode silent
      ${pathPreamble}
      record gif
      echo "GIF recording toggled"
    ''
    // mkScript "read-aloud" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Read Selection Aloud (toggle)
      # @vicinae.mode silent
      ${pathPreamble}
      read-aloud --toggle
      echo "Read-aloud toggled"
    ''
    // mkScript "timer" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Timer (minutes)
      # @vicinae.mode compact
      # @vicinae.argument1 { "type": "text", "placeholder": "minutes" }
      # @vicinae.argument2 { "type": "text", "placeholder": "what for (optional)", "optional": true }
      ${pathPreamble}
      leader-timer "$1" "''${2:-}" || exit
      echo "Timer set: $1 min''${2:+ — $2}"
    ''
    # The message argument is required. It used to be optional, which fell
    # through to a bare `send-to-phone-ntfy` — that reads the message from
    # stdin, and a script command has no stdin, so it always died with
    # "Error: empty message". The wrapper then printed "Sent to phone" anyway
    # and exited 0, so the palette showed a success toast for a push that was
    # never sent and the AUTOFIX watcher never saw it.
    // mkScript "send-to-phone" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Send Text to Phone (ntfy)
      # @vicinae.mode compact
      # @vicinae.argument1 { "type": "text", "placeholder": "message" }
      ${pathPreamble}
      send-to-phone-ntfy "$1" || exit
      echo "Sent to phone"
    ''
    // mkScript "session-restore" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Restore Hyprland Session (windows/workspaces)
      # @vicinae.mode compact
      ${pathPreamble}
      hyprland-session-restore || exit
      echo "Session restore triggered"
    ''
    // mkScript "wallpaper" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Change Wallpaper
      # @vicinae.mode silent
      ${pathPreamble}
      wallpaper-picker
      echo "Wallpaper picker done"
    ''
    // mkScript "keybinds" ''
      #!/usr/bin/env bash
      # @vicinae.schemaVersion 1
      # @vicinae.title Show Keybinds Cheatsheet
      # @vicinae.mode silent
      ${pathPreamble}
      keybinds
      echo "Keybinds shown"
    '';
  home = config.home.homeDirectory;

  # Vicinae's file indexer indexes `indexingPaths` (upstream default: $HOME)
  # with `excludedIndexingPaths` defaulting to an EMPTY list. On this machine
  # that scope is unservable: 1.75M files, dominated by directories that are
  # machine-generated and written to continuously.
  #
  # The failure is a livelock, not just slowness. Every write into a watched
  # directory fires inotify, which queues an incremental rescan; the rescan can
  # never outrun the write rate, so the queue never drains. Measured on
  # 2026-07-27: 8554 of 8564 rows in the indexer's own scan_history were
  # rejected as "already running", 257 scan attempts landed in a single minute,
  # exactly one full scan has ever completed (2026-07-26 08:00), and one thread
  # sat pinned at ~97% CPU pushing ~18 GB of writes per half hour into a 2.7 GB
  # SQLite index with a 318 MB WAL.
  #
  # Each exclusion below is a measured offender, not a guess:
  #   lifelog                     326k files / 122 GB, +~10 files/min forever
  #   Obsidian/.stversions         81k Syncthing version copies (also dupes in
  #                                search results — they shadow the real notes)
  #   .zen                        135k browser profile; sessionstore-backups
  #                                and glean/db rewrite constantly
  #   .config                      64k app state (Beeper sdk-tmp, Claude
  #                                IndexedDB, Slack, syncthing index-v2/.tmp)
  #   .claude                      37k session/shell-snapshot/heartbeat churn
  #   .local/state, .local/share/activitywatch
  #                                few files but near-continuous sqlite writes;
  #                                activitywatch was the single most-rescanned
  #                                path (395 attempts) despite holding 16 files
  #   .mutagen                     29k sync-daemon state
  # `.cache`, `node_modules` and `.git` are already skipped by the indexer
  # (verified: 0 rows each), so they are deliberately not repeated here.
  indexerExcludes = [
    "${home}/lifelog"
    "${home}/Obsidian/.stversions"
    "${home}/.zen"
    "${home}/.config"
    "${home}/.claude"
    "${home}/.local/state"
    "${home}/.local/share/activitywatch"
    "${home}/.mutagen"
  ];
in {
  home.packages = [pkgs.vicinae];

  # Owned declaratively so the exclusions survive a rebuild. Trade-off: changes
  # made in Vicinae's settings GUI can no longer persist to this file — edit it
  # here instead. Vicinae merges this over its built-in defaults, so only the
  # keys that differ from upstream need to appear.
  xdg.configFile."vicinae/settings.json".text = builtins.toJSON {
    "$schema" = "https://vicinae.com/schemas/config.json";
    providers.files.preferences = {
      autoIndexing = true;
      indexingPaths = [home];
      excludedIndexingPaths = indexerExcludes;
    };
  };

  # Use a stable path that Hyprland can execute even before a newly activated
  # Home Manager package profile has propagated into its process environment.
  home.file.".local/bin/vicinae-toggle" = {
    executable = true;
    source = "${vicinaeToggle}/bin/vicinae-toggle";
  };

  xdg.dataFile = scripts;

  # On-demand only — no [Install] section, so it never autostarts; the vicinae
  # white-noise script starts/stops it. Owning the player as a unit is what makes
  # the toggle survive Vicinae reaping its script's process group.
  systemd.user.services.white-noise = {
    Unit = {
      Description = "Brown noise generator (mpv lavfi anoisesrc)";
      After = ["pipewire.service"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.mpv}/bin/mpv --no-video --no-terminal --volume=60 av://lavfi:anoisesrc=color=brown:amplitude=0.5";
      Restart = "no";
    };
  };

  systemd.user.services.vicinae = {
    Unit = {
      Description = "Vicinae launcher server";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      # Global QT_QPA_PLATFORM=xcb (hyprland/variables.nix, for qt5ct theming
      # elsewhere) breaks Vicinae's Qt plugin load and crash-loops the server
      # (core-dump: "Could not load the Qt platform plugin xcb"). Vicinae is
      # Wayland-native, so force it back to wayland just for this unit.
      Environment = ["QT_QPA_PLATFORM=wayland"];
      ExecStart = vicinaeServer;
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
