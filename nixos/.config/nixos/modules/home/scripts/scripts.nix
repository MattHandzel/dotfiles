{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  # Platform test from the `host` specialArg, not from `pkgs` — see the
  # comment at the top of lib/scheduled.nix for why.
  isDarwin = host == "mac";
  isLinux = !isDarwin;
  inherit (import ../lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
  platform = import ../lib/platform-scripts.nix {inherit pkgs;};

  # Helper function to create a shell script bin
  # reboot-state: save Claude Code sessions / tmux shells / windows, reboot, pick what
  # comes back (Python; source in ./scripts/reboot-state.py). Doc: areas/second-brain/reboot-state.md
  rebootState = pkgs.writeScriptBin "reboot-state" (
    "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ./scripts/reboot-state.py
  );
  removeShExtension = str: builtins.replaceStrings [".sh"] [""] str;
  makeShellScriptBin = script: pkgs.writeShellScriptBin (removeShExtension (builtins.baseNameOf script)) (builtins.readFile script);

  # Scripts that are pure CLI (or reach the desktop only through the
  # platform shims in ../lib/platform-scripts.nix) run unmodified on macOS.
  sharedScripts = [
    ./scripts/maxfetch.sh
    ./scripts/compress.sh
    ./scripts/extract.sh
    ./scripts/ascii.sh
    ./scripts/tmux-sessionizer.sh
    ./scripts/lifelog-search.sh
    ./scripts/glucose.sh
    ./scripts/password-picker.sh
    ./scripts/run-nix-shell-on-new-tmux-session.sh
    ./scripts/notify-if-command-is-successful.sh
    ./scripts/take-note.sh
    ./scripts/quick-capture.sh
    ./scripts/copy-to-clipboard.sh
    ./scripts/process-log.sh
    ./scripts/transcribe_captures.sh
    ./scripts/TextToSpeechService.sh
    ./scripts/prompt-picker.sh
    ./scripts/smart-clipboard-picker.sh
    ./scripts/grammar-check.sh # SUPER+C — LanguageTool on current selection
    ./scripts/paste-second-clip.sh
    ./scripts/claude-ask.sh
    ./scripts/send-to-phone-ntfy.sh
    # MAT-572 — power-tooling parallels from Saul's Mac list
    ./scripts/clip2md.sh # clipboard rich-text -> Markdown (SUPER+SHIFT+M)
    ./scripts/screenshot-search.sh # fuzzel picker over ~/Pictures/Screenshots (SUPER+SHIFT+S)
    ./scripts/leader-timer.sh # N-minute timer behind the SUPER+SHIFT+SPACE leader submap
    ./scripts/pl-assist # Polish capture: bare-bones fast Claude helper (MAT-799)
    ./scripts/pl-capture # Polish capture: numpad-8 mode menu + file router (MAT-800)
  ];

  # Hyprland / Wayland / NixOS-specific: these talk to hyprctl, the Wayland
  # compositor, chromium --app wrappers, or systemd. macOS equivalents are
  # Phase 6 work on the Mac — see docs/mac-migration/TODO-path-inputs.md.
  linuxScripts = [
    ./scripts/wall-change.sh
    ./scripts/wallpaper-picker.sh
    ./scripts/runbg.sh
    ./scripts/music.sh
    ./scripts/lofi.sh
    ./scripts/toggle_blur.sh
    ./scripts/toggle_oppacity.sh
    ./scripts/shutdown-script.sh
    ./scripts/keybinds.sh
    ./scripts/vm-start.sh
    ./scripts/record.sh
    ./scripts/brightness.sh
    ./scripts/secondary-monitor-update.sh
    ./scripts/focus_app.sh
    ./scripts/toggle-focus-mode.sh
    ./scripts/focus-distracting-apps.sh
    ./scripts/focus-delay-gate.sh
    ./scripts/switch-workspace-to-other-monitor.sh
    ./scripts/run-command-based-on-type-of-workspace.sh
    ./scripts/kill-window-and-switch.sh
    ./scripts/calendar.sh
    ./scripts/notion-calendar.sh
    ./scripts/superhuman.sh
    ./scripts/shortwave.sh
    ./scripts/otter.sh
    ./scripts/tasker.sh
    ./scripts/record-lecture.sh
    ./scripts/audio-log.sh
    ./scripts/screen-log.sh
    ./scripts/suspend-script-runner.sh
    ./scripts/notetaker.sh
    ./scripts/track_window_history.sh
    ./scripts/track_workspace_history.sh
    ./scripts/wispr-hub.sh
    ./scripts/wispr-status.sh # waybar: Wispr running / dictating
    ./scripts/open-website-as-standalone-app.sh
    ./scripts/claude.ai.sh
    ./scripts/com.anthropic.Claude.sh
    ./scripts/gemini.google.com.sh
    ./scripts/linear.sh
    ./scripts/zoom-web.sh
    ./scripts/toggle-stt.sh
    ./scripts/kb-lang-status.sh
    ./scripts/btop-gui.sh
    ./scripts/yazi-gui.sh
    ./scripts/ntfy-gui.sh
    ./scripts/system-fix.sh
    ./scripts/nixos-assistant.sh
    ./scripts/hyprland-session-save.sh # snapshot windows/workspaces (timer in hyprland/hyprsession.nix)
    ./scripts/hyprland-session-restore.sh # relaunch saved windows on their workspaces
  ];

  shellScripts = sharedScripts ++ lib.optionals isLinux linuxScripts;

  # Create shell script bins
  shellScriptBins = map makeShellScriptBin shellScripts;

  # auth-code-watcher is Python (stdlib only), so wrap it to run under python3
  # rather than going through makeShellScriptBin.
  authCodeWatcher = pkgs.writeShellScriptBin "auth-code-watcher" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/auth-code-watcher.py} "$@"
  '';

  # Drafting-velocity tracker behind the waybar "custom/writing" module and the
  # :WriteFast nvim commands. Stdlib-only Python; daemonless (waybar's poll of
  # `status --json` is what advances the session).
  writingSession = pkgs.writeShellScriptBin "writing-session" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/writing-session.py} "$@"
  '';

  # Create/inspect Zen Browser Spaces, which live as JSON inside the mozLz4
  # session store. Refuses to write while the profile is locked — Zen rewrites
  # that file from memory, so an edit made while it runs silently disappears.
  zenSpaces = pkgs.writeShellScriptBin "zen-spaces" ''
    exec ${pkgs.python3.withPackages (ps: [ps.lz4])}/bin/python3 ${./scripts/zen-spaces.py} "$@"
  '';

  # Backs the waybar "custom/agenda" slot (now / next calendar event). Stdlib-only:
  # it reads the cache written by calendar-agenda.service and does no network I/O,
  # so waybar can poll it every 30s for a live countdown.
  waybarAgenda = pkgs.writeShellScriptBin "waybar-agenda" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/waybar-agenda.py} "$@"
  '';

  # Built as their own derivations (not via the shellScripts list) so the systemd
  # services can reference their store paths.
  focusEnforcer = makeShellScriptBin ./scripts/focus-mode-enforcer.sh;
  focusModeSync = makeShellScriptBin ./scripts/focus-mode-sync.sh;

  # Helper bins the focus scripts shell out to (kept as store paths so the
  # enforcer's restricted systemd PATH can reach them).
  focusDistractingApps = makeShellScriptBin ./scripts/focus-distracting-apps.sh;
  focusDelayGate = makeShellScriptBin ./scripts/focus-delay-gate.sh;
  toggleFocusMode = makeShellScriptBin ./scripts/toggle-focus-mode.sh;

  # ntfy → desktop notifications subscriber (own derivation so the service can
  # reference its store path and re-exec itself as the message handler).
  ntfyDesktopSub = makeShellScriptBin ./scripts/ntfy-desktop-sub.sh;
in {
  config = lib.mkMerge [
    {
      home.packages =
        shellScriptBins
        ++ [
          rebootState
          authCodeWatcher
          # link-search and read-aloud are Linux-only: their runtimeInputs are
          # cliphist, wl-clipboard, hyprland, fuzzel and libnotify, none of which
          # build on darwin. They live in the isLinux block below. Porting them
          # means routing through platform.nix (clip-copy / clip-paste / notify).
        ]
        ++ (with pkgs; [
          bc # for brightness script
          gum # run-nix-shell-on-new-tmux-session requires this
          jq
          pass # password-picker: GPG-encrypted password store
          gnupg # pass backend (gpg-agent caches the passphrase)
          nmap # for looking at devices on the wifi
          ffmpeg
        ]);
    }

    (lib.optionalAttrs isLinux {
      home.packages =
        [
          (import ./scripts/link-search/default.nix {inherit pkgs;})
          (import ./scripts/read-aloud/default.nix {inherit pkgs;})
        ]
        ++ (with pkgs; [
          ddcutil # for brightness script
          socat # focus-mode-enforcer reads the Hyprland event socket
          # quick capture
          zenity
          wl-clipboard
          grim
          wf-recorder
          alsa-utils # for arecord
        ])
        ++ [
          (import ./scripts/ocr-screenshot/default.nix {inherit pkgs;})
          writingSession
          waybarAgenda
          zenSpaces
          focusEnforcer
          ntfyDesktopSub
          (import ./scripts/kbshot/default.nix {inherit pkgs;})
        ];

      # GUI ntfy client: a standalone web-app window for the server's ntfy web UI,
      # launchable from the app launcher.
      xdg.desktopEntries.ntfy = {
        name = "ntfy";
        genericName = "Push Notifications";
        comment = "Browse ntfy topics and messages";
        exec = "ntfy-gui";
        icon = "dialog-information";
        type = "Application";
        categories = ["Network" "Utility"];
        settings.StartupWMClass = "ntfy";
      };

      # Superhuman: no Linux client exists, so this is the chromium --app wrapper
      # (see scripts/superhuman.sh, which puts itself in app-webapps.slice). Without
      # a desktop entry the launcher never surfaced it in Vicinae. StartupWMClass is
      # the class Chromium actually sets for this --app window, read off hyprctl
      # rather than guessed:
      #   class: chrome-mail.superhuman.com__-Default
      xdg.desktopEntries.superhuman = {
        name = "Superhuman";
        genericName = "Email";
        comment = "Superhuman Mail (web app)";
        exec = "superhuman";
        icon = "mail-unread";
        type = "Application";
        categories = ["Network" "Email"];
        settings.StartupWMClass = "chrome-mail.superhuman.com__-Default";
      };

      # Shortwave: AI email client, web-only like Superhuman, so the same chromium
      # --app wrapper (see scripts/shortwave.sh). No browser extension needed here --
      # app.shortwave.com is a real web app, not an extension-injected host page.
      # StartupWMClass read off hyprctl after launching, not guessed:
      #   class: chrome-app.shortwave.com__-Default
      xdg.desktopEntries.shortwave = {
        name = "Shortwave";
        genericName = "Email";
        comment = "Shortwave AI email (web app)";
        exec = "shortwave";
        icon = "mail-unread";
        type = "Application";
        categories = ["Network" "Email"];
        settings.StartupWMClass = "chrome-app.shortwave.com__-Default";
      };

      # Otter.ai: transcription service, web-only on Linux, so the same chromium
      # --app wrapper (see scripts/otter.sh). StartupWMClass read off hyprctl after
      # launching, not guessed:
      #   class: chrome-otter.ai__home-Default
      xdg.desktopEntries.otter = {
        name = "Otter.ai";
        genericName = "Transcription";
        comment = "Otter.ai meeting transcription (web app)";
        exec = "otter";
        icon = "audio-input-microphone";
        type = "Application";
        categories = ["Network" "AudioVideo"];
        settings.StartupWMClass = "chrome-otter.ai__home-Default";
      };

      # Always-on Focus Mode enforcer: stays connected to the Hyprland event socket
      # and only acts when /tmp/focus_mode exists. Always-running (rather than
      # launched from the toggle button) so it reliably has the session env + socket.
      # Hyprland-socket bound, so it stays Linux-only: the macOS focus story is the
      # server's blocky DNS over Tailscale (Phase 8), not a window-event enforcer.
      systemd.user.services.focus-mode-enforcer = {
        Unit = {
          Description = "Focus Mode enforcer — block-then-allow delay for distracting apps";
          After = ["graphical-session.target"];
          PartOf = ["graphical-session.target"];
        };
        Service = {
          ExecStart = "${focusEnforcer}/bin/focus-mode-enforcer";
          Environment = ["PATH=${pkgs.lib.makeBinPath [focusDistractingApps focusDelayGate pkgs.hyprland pkgs.jq pkgs.socat pkgs.zenity pkgs.libnotify pkgs.coreutils pkgs.gnugrep]}"];
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = ["graphical-session.target"];
      };

      # Calendar-driven Focus Mode: subscribe to the server resolver's ntfy
      # `focus-mode` topic and force the laptop's /tmp/focus_mode flag to follow the
      # Life Scheduler calendar (calendar wins). Self-healing: holds last state on any
      # network error, replays recent transitions on (re)connect.
      systemd.user.services.focus-mode-sync = {
        Unit = {
          Description = "Sync laptop Focus Mode to the calendar (ntfy focus-mode topic)";
          After = ["graphical-session.target" "network-online.target"];
          PartOf = ["graphical-session.target"];
        };
        Service = {
          ExecStart = "${focusModeSync}/bin/focus-mode-sync";
          Environment = ["PATH=${pkgs.lib.makeBinPath [toggleFocusMode pkgs.curl pkgs.jq pkgs.libnotify pkgs.coreutils pkgs.hyprland]}"];
          Restart = "always";
          RestartSec = 10;
        };
        Install.WantedBy = ["graphical-session.target"];
      };
    })

    (lib.optionalAttrs isDarwin {
      home.packages = [pkgs.terminal-notifier pkgs.choose-gui pkgs.pngpaste];
    })

    # ntfy → native desktop notifications for Matt's topics. Always-on user service;
    # the real ntfy-sh binary (not the zsh `ntfy` curl-wrapper function) is on PATH
    # here, so `ntfy subscribe` works.
    (lib.optionalAttrs isLinux (scheduled {
      name = "ntfy-desktop-sub";
      description = "Surface ntfy messages as desktop notifications";
      command = ["${ntfyDesktopSub}/bin/ntfy-desktop-sub"];
      oneshot = false;
      after = ["graphical-session.target" "network-online.target"];
      partOf = ["graphical-session.target"];
      restart = "always";
      restartSec = 10;
      install.WantedBy = ["graphical-session.target"];
      linuxPathPackages = [pkgs.ntfy-sh pkgs.libnotify pkgs.bash pkgs.coreutils];
    }))

    # Watch Gmail for login/verification codes and surface them (notify + copy to
    # clipboard), the way Beeper does for texted codes. The Gmail app password is
    # read at runtime from ~/notes/.env (APP_PASSWORD) so no secret enters the Nix
    # store. import-environment (Hyprland exec-once) gives the service WAYLAND_DISPLAY
    # + DBUS so notify-send / wl-copy reach the session; on macOS a LaunchAgent
    # already runs in the user's GUI session, so no equivalent is needed.
    (scheduled {
      name = "auth-code-watcher";
      description = "Watch Gmail for login/verification codes → notify + copy to clipboard";
      command = ["${authCodeWatcher}/bin/auth-code-watcher"];
      oneshot = false;
      after = ["graphical-session.target" "network-online.target"];
      partOf = ["graphical-session.target"];
      restart = "on-failure";
      restartSec = 30;
      install.WantedBy = ["graphical-session.target"];
      linuxPathPackages = [pkgs.wl-clipboard pkgs.libnotify pkgs.coreutils];
      keepAlive = true;
      path = [platform.clip-copy platform.notify pkgs.coreutils];
      logFile = "%h/.local/state/auth-code-watcher.log";
    })
  ];
}
