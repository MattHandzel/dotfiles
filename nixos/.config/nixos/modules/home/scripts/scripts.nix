{pkgs, ...}: let
  # Helper function to create a shell script bin
  removeShExtension = str: builtins.replaceStrings [".sh"] [""] str;
  makeShellScriptBin = script: pkgs.writeShellScriptBin (removeShExtension (builtins.baseNameOf script)) (builtins.readFile script);

  # List of shell scripts
  shellScripts = [
    ./scripts/wall-change.sh
    ./scripts/wallpaper-picker.sh
    ./scripts/runbg.sh
    ./scripts/music.sh
    ./scripts/lofi.sh
    ./scripts/toggle_blur.sh
    ./scripts/toggle_oppacity.sh
    ./scripts/maxfetch.sh
    ./scripts/compress.sh
    ./scripts/extract.sh
    ./scripts/shutdown-script.sh
    ./scripts/keybinds.sh
    ./scripts/vm-start.sh
    ./scripts/ascii.sh
    ./scripts/record.sh
    ./scripts/brightness.sh
    ./scripts/secondary-monitor-update.sh
    ./scripts/tmux-sessionizer.sh
    ./scripts/focus_app.sh
    ./scripts/toggle-focus-mode.sh
    ./scripts/focus-distracting-apps.sh
    ./scripts/focus-delay-gate.sh
    ./scripts/password-picker.sh
    ./scripts/run-nix-shell-on-new-tmux-session.sh
    ./scripts/notify-if-command-is-successful.sh
    ./scripts/switch-workspace-to-other-monitor.sh
    ./scripts/run-command-based-on-type-of-workspace.sh
    ./scripts/kill-window-and-switch.sh
    ./scripts/take-note.sh
    ./scripts/calendar.sh
    ./scripts/tasker.sh
    ./scripts/quick-capture.sh
    ./scripts/copy-to-clipboard.sh
    ./scripts/record-lecture.sh
    ./scripts/audio-log.sh
    ./scripts/screen-log.sh
    ./scripts/process-log.sh
    ./scripts/suspend-script-runner.sh
    ./scripts/notetaker.sh
    ./scripts/track_window_history.sh
    ./scripts/track_workspace_history.sh
    ./scripts/transcribe_captures.sh
    ./scripts/TextToSpeechService.sh
    ./scripts/prompt-picker.sh
    ./scripts/smart-clipboard-picker.sh
    ./scripts/open-website-as-standalone-app.sh
    ./scripts/claude.ai.sh
    ./scripts/claude-ask.sh
    ./scripts/gemini.google.com.sh
    ./scripts/linear.sh
    ./scripts/toggle-stt.sh
    ./scripts/kb-lang-status.sh
    ./scripts/btop-gui.sh
    ./scripts/yazi-gui.sh
    ./scripts/send-to-phone-ntfy.sh
    ./scripts/ntfy-gui.sh
    ./scripts/system-fix.sh
    ./scripts/nixos-assistant.sh
    # MAT-572 — power-tooling parallels from Saul's Mac list
    ./scripts/clip2md.sh # clipboard rich-text -> Markdown (SUPER+SHIFT+M)
    ./scripts/screenshot-search.sh # fuzzel picker over ~/Pictures/Screenshots (SUPER+SHIFT+S)
    ./scripts/leader-timer.sh # N-minute timer behind the SUPER+SHIFT+SPACE leader submap
    ./scripts/pl-assist # Polish capture: bare-bones fast Claude helper (MAT-799)
    ./scripts/pl-capture # Polish capture: numpad-8 mode menu + file router (MAT-800)
  ];

  # Create shell script bins
  shellScriptBins = map makeShellScriptBin shellScripts;

  # auth-code-watcher is Python (stdlib only), so wrap it to run under python3
  # rather than going through makeShellScriptBin.
  authCodeWatcher = pkgs.writeShellScriptBin "auth-code-watcher" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/auth-code-watcher.py} "$@"
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
  home.packages = with pkgs;
    shellScriptBins
    ++ [
      bc # for brightness script
      ddcutil # for brightness script
      gum # run-nix-shell-on-new-tmux-session requires this
      jq
      socat # focus-mode-enforcer reads the Hyprland event socket
      pass # password-picker: GPG-encrypted password store
      gnupg # pass backend (gpg-agent caches the passphrase)
      nmap # for looking at devices on the wifi

      # quick capture
      zenity
      wl-clipboard
      grim
      wf-recorder
      alsa-utils # for arecord
      ffmpeg
    ]
    ++ [
      (import ./scripts/ocr-screenshot/default.nix {inherit pkgs;})
      authCodeWatcher
      focusEnforcer
      ntfyDesktopSub
      (import ./scripts/link-search/default.nix {inherit pkgs;})
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

  # ntfy → native desktop notifications for Matt's topics. Always-on user service;
  # the real ntfy-sh binary (not the zsh `ntfy` curl-wrapper function) is on PATH
  # here, so `ntfy subscribe` works.
  systemd.user.services.ntfy-desktop-sub = {
    Unit = {
      Description = "Surface ntfy messages as desktop notifications";
      After = ["graphical-session.target" "network-online.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${ntfyDesktopSub}/bin/ntfy-desktop-sub";
      Environment = ["PATH=${pkgs.lib.makeBinPath [pkgs.ntfy-sh pkgs.libnotify pkgs.bash pkgs.coreutils]}"];
      Restart = "always";
      RestartSec = 10;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  # Always-on Focus Mode enforcer: stays connected to the Hyprland event socket
  # and only acts when /tmp/focus_mode exists. Always-running (rather than
  # launched from the toggle button) so it reliably has the session env + socket.
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

  # Watch Gmail for login/verification codes and surface them (notify + copy to
  # clipboard), the way Beeper does for texted codes. The Gmail app password is
  # read at runtime from ~/notes/.env (APP_PASSWORD) so no secret enters the Nix
  # store. import-environment (Hyprland exec-once) gives the service WAYLAND_DISPLAY
  # + DBUS so notify-send / wl-copy reach the session.
  systemd.user.services.auth-code-watcher = {
    Unit = {
      Description = "Watch Gmail for login/verification codes → notify + copy to clipboard";
      After = ["graphical-session.target" "network-online.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${authCodeWatcher}/bin/auth-code-watcher";
      Environment = ["PATH=${pkgs.lib.makeBinPath [pkgs.wl-clipboard pkgs.libnotify pkgs.coreutils]}"];
      Restart = "on-failure";
      RestartSec = 30;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
