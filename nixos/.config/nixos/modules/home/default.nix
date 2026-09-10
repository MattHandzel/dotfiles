{
  inputs,
  host,
  lib,
  ...
}: let
  # The platform test here MUST come from `host` (a specialArg), not from
  # `pkgs.stdenv.hostPlatform`. `imports` is evaluated before `_module.args` is
  # resolved, so reading `pkgs` here is an infinite recursion — the module
  # system says as much and then truncates the trace. specialArgs are available
  # at import time by construction, which is exactly why they exist.
  # Every OTHER module in this tree branches on `pkgs.stdenv.hostPlatform`,
  # because those branches live in `config`, where `pkgs` is already available.
  isDarwin = host == "mac";
  isLinux = !isDarwin;

  # Everything here evaluates on BOTH NixOS and nix-darwin. Modules that need a
  # per-platform branch do it internally (btop's nvtop, tmux's shell path, zsh's
  # aliases, gtk's fontconfig-vs-gtk split) rather than being forked.
  shared = [
    ./theme.nix # palette/font tokens shared across modules
    ./platform.nix # clip-copy / clip-paste / notify / open-it / pick / type-text
    ./bat.nix # better cat command
    ./btop.nix # resouces monitor
    ./git.nix # version control
    ./gtk.nix # fonts on both; the gtk.* theme block is Linux-gated inside
    ./kitty.nix # terminal
    ./nvim.nix # neovim editor
    ./packages.nix # other packages
    ./scripts/scripts.nix # personal scripts
    ./starship.nix # shell prompt
    ./tmux.nix # terminal multiplexer
    ./vscodium.nix # vscode forck
    ./zsh.nix # shell
    ./services.nix
    ./health-dashboard.nix # daily 09:00 health-data import timer
    ./todoist.nix
    ./transcribe-captures.nix
    ./luck-scheduler.nix
    ./polish-pipeline.nix
    # keep the rotating OAuth token out of Syncthing (daily forced re-login)
    ./claude-syncthing-ignores.nix
    ./linear-notify.nix # poll Linear → desktop notifications
    ./predict-ui.nix # prediction-tracker resolve frontend on localhost:7337
    ./privacy-card.nix # agent-issuable capped virtual cards (Privacy.com API)
    # periodic markdown ↔ Google Docs reconcile (timer, not a 15s watch loop)
    ./gdoc-sync.nix
    # a shareable Google Doc per upcoming meeting note (the server writes the
    # notes; gdoc-sync only lives here, so the Doc half runs on the laptop)
    ./meeting-note-docs.nix
    inputs.catppuccin.homeModules.catppuccin
  ];

  # Hyprland, Wayland, XDG desktop entries, systemd-only guards, and Linux-only
  # applications. None of these have a meaning on macOS.
  linuxOnly = [
    ./aseprite/aseprite.nix # pixel art editor
    ./audacious/audacious.nix # music player
    ./discord.nix # discord with catppuccin theme
    ./fuzzel.nix # launcher
    ./hyprland # window manager
    ./swaync/swaync.nix # notification deamon
    ./waybar # status bar
    ./thunderbird.nix # thunder bird
    ./memwatch.nix
    ./electron-app-daily-restart.nix
    ./zen-config.nix
    ./app-memory-caps.nix
    ./lifelog-collector.nix
    # ActivityWatch as durable systemd user services (aw-server + watchers)
    ./activitywatch.nix
    # delete foreign symlinks (manual `systemctl --user enable` leftovers)
    # that would otherwise abort activation with "would be clobbered"
    ./hm-clobber-guard.nix
    # say so out loud when a boot reverts an hm-switch that no rebuild baked
    ./hm-drift-guard.nix
    # e-book reader (default for epub/mobi/azw3/fb2/cbz); fixes the packaged
    # desktop entry, which is missing the %U that makes "open with" work
    ./foliate.nix
    ./readest.nix
    # voice dictation (unofficial Linux AppImage port)
    ./wispr-flow.nix
    # un-stick modifiers that Wispr's uinput keyboard strands
    ./stuck-key-guard.nix
    # let Wispr see hot-plugged keyboards (the BT TOTEM) without restarting it
    ./kbd-relay.nix
    # Raycast-style command palette (SUPER+D) — launch/run/timer/calc
    ./vicinae.nix
    # Google Drive rclone mount at ~/gdrive (remote configured once by hand)
    ./gdrive-mount.nix
    ./linux/mimeapps.nix
    # logged script/service failure → headless Claude Opus diagnoses + fixes it
    # DISABLED 2026-07-24: the watcher spawned 11 headless Opus repairs in one day
    # across 3 units without converging (focus-state-agent ×8, bt-keyboard-reconnect,
    # lifelog-collector). The daily cap does not increment, so the 30-min cooldown was
    # the only brake — ~48 Opus runs/day/subject. Re-enable only after the cap is fixed
    # and a per-subject attempt limit exists. See capture/2026-07-24-claude-usage-audit.md
    # ./claude-autofix.nix
    # ./notion.nix
    # ./ntfy.nix
  ];
in {
  imports = shared ++ lib.optionals isLinux linuxOnly ++ lib.optionals isDarwin [./darwin];

  catppuccin = {
    flavor = "mocha";
    enable = true;
    # Catppuccin's VSCode module pulls/builds a theme extension; keep it off so
    # rebuilds don't depend on npm registry availability.
    vscode.profiles.default.enable = false;
    # nvim.enable = false;
  };
  catppuccin.delta.enable = false;

  programs.atuin = {
    enable = true;
    settings = {
      accept_past_line_end = true;
      auto_sync = true;
      sync_frequency = "5m";
      sync_address = "https://api.atuin.sh";
      search_mode = "fuzzy";
      keymap_mode = "vim-normal";
      enter_accept = true;
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      # todo: write
    };
  };

  home.sessionVariables = {
    TERMINAL = "kitty";
    EDITOR = "nvim";
    # GDK_BACKEND = "x11"; # Forces XWayland for GTK apps like Foliate
  };
}
