{
  inputs,
  username,
  host,
  ...
}: {
  imports =
    [(import ./aseprite/aseprite.nix)] # pixel art editor
    ++ [(import ./audacious/audacious.nix)] # music player
    ++ [(import ./theme.nix)] # palette/font tokens shared across modules
    ++ [(import ./bat.nix)] # better cat command
    ++ [(import ./btop.nix)] # resouces monitor
    # ++ [(import ./cava.nix)] # audio visualizer
    ++ [(import ./discord.nix)] # discord with catppuccin theme
    ++ [(import ./fuzzel.nix)] # launcher
    ++ [(import ./git.nix)] # version control
    ++ [(import ./gtk.nix)] # gtk theme
    ++ [(import ./hyprland)] # window manager
    ++ [(import ./kitty.nix)] # terminal
    ++ [(import ./swaync/swaync.nix)] # notification deamon
    ++ [(import ./nvim.nix)] # neovim editor
    ++ [(import ./packages.nix)] # other packages
    ++ [(import ./scripts/scripts.nix)] # personal scripts
    # ++ [(import ./spicetify.nix)] # spotify client
    ++ [(import ./starship.nix)] # shell prompt
    # swaylock removed — using hyprlock instead
    ++ [(import ./vscodium.nix)] # vscode forck
    ++ [(import ./waybar)] # status bar
    ++ [(import ./zsh.nix)] # shell
    ++ [(import ./thunderbird.nix)] # thunder bird
    ++ [(import ./tmux.nix)] # terminal multiplexer
    ++ [(import ./services.nix)]
    ++ [(import ./health-dashboard.nix)] # daily 09:00 health-data import timer
    ++ [(import ./todoist.nix)]
    ++ [./transcribe-captures.nix]
    ++ [./luck-scheduler.nix]
    ++ [./polish-pipeline.nix]
    ++ [./memwatch.nix]
    ++ [./electron-app-daily-restart.nix]
    ++ [./health-dashboard.nix]
    ++ [./zen-config.nix]
    ++ [./app-memory-caps.nix]
    ++ [./lifelog-collector.nix]
    # ActivityWatch as durable systemd user services (aw-server + watchers)
    ++ [./activitywatch.nix]
    # delete foreign symlinks (manual `systemctl --user enable` leftovers)
    # that would otherwise abort activation with "would be clobbered"
    ++ [./hm-clobber-guard.nix]
    # say so out loud when a boot reverts an hm-switch that no rebuild baked
    ++ [./hm-drift-guard.nix]
    # keep the rotating OAuth token out of Syncthing (daily forced re-login)
    ++ [./claude-syncthing-ignores.nix]
    ++ [./linear-notify.nix] # poll Linear → swaync desktop notifications
    ++ [./predict-ui.nix] # prediction-tracker resolve frontend on localhost:7337
    ++ [./privacy-card.nix] # agent-issuable capped virtual cards (Privacy.com API)
    ++ [inputs.catppuccin.homeModules.catppuccin]
    ++ [(import ./foliate.nix)]
    # e-book reader (default for epub/mobi/azw3/fb2/cbz); fixes the packaged
    # desktop entry, which is missing the %U that makes "open with" work
    ++ [(import ./readest.nix)]
    # voice dictation (unofficial Linux AppImage port)
    ++ [./wispr-flow.nix]
    # un-stick modifiers that Wispr's uinput keyboard strands
    ++ [./stuck-key-guard.nix]
    # let Wispr see hot-plugged keyboards (the BT TOTEM) without restarting it
    ++ [./kbd-relay.nix]
    # Raycast-style command palette (SUPER+D) — launch/run/timer/calc
    ++ [./vicinae.nix]
    # periodic markdown ↔ Google Docs reconcile (timer, not a 15s watch loop)
    ++ [./gdoc-sync.nix]
    # Google Drive rclone mount at ~/gdrive (remote configured once by hand)
    ++ [./gdrive-mount.nix]
    # a shareable Google Doc per upcoming meeting note (the server writes the
    # notes; gdoc-sync only lives here, so the Doc half runs on the laptop)
    ++ [./meeting-note-docs.nix]
    # logged script/service failure → headless Claude Opus diagnoses + fixes it
    # DISABLED 2026-07-24: the watcher spawned 11 headless Opus repairs in one day
    # across 3 units without converging (focus-state-agent ×8, bt-keyboard-reconnect,
    # lifelog-collector). The daily cap does not increment, so the 30-min cooldown was
    # the only brake — ~48 Opus runs/day/subject. Re-enable only after the cap is fixed
    # and a per-subject attempt limit exists. See capture/2026-07-24-claude-usage-audit.md
    # ++ [./claude-autofix.nix]
    # ++ [(import ./notion.nix)]
    # ++ [(import ./ntfy.nix)]
    ;

  catppuccin = {
    flavor = "mocha";
    enable = true;
    # Catppuccin's VSCode module pulls/builds a theme extension; keep it off so
    # rebuilds don't depend on npm registry availability.
    vscode.profiles.default.enable = false;
    # nvim.enable = false;
  };
  catppuccin.delta.enable = false;

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = "yazi.desktop";
      "text/plain" = "nvim.desktop";
      "text/x-python" = "nvim.desktop";
      "text/html" = "zen-beta.desktop";
      "x-scheme-handler/http" = "zen-beta.desktop";
      "x-scheme-handler/https" = "zen-beta.desktop";
      "audio/*" = "mpv.desktop";
      "video/*" = "mpv.desktop";
      "image/*" = "swayimg.desktop";
      "text/css" = "nvim.desktop";
      "text/*" = "nvim.desktop";
      "application/json" = "nvim.desktop";
      "application/x-shellscript" = "nvim.desktop";
      # PDFs stay with zathura — readest claims application/pdf upstream, but
      # its PDF support is experimental and zathura/sioyek are the tools here.
      "application/pdf" = "zathura.desktop";
      # Book formats open in Readest (see modules/home/readest.nix). Previously
      # EPUB went to calibre-ebook-viewer.desktop; calibre stays installed as a
      # library manager, it is just no longer what opens a book on double-click.
      "application/epub+zip" = "readest.desktop";
      "application/x-mobipocket-ebook" = "readest.desktop";
      "application/vnd.amazon.ebook" = "readest.desktop";
      "application/vnd.amazon.mobi8-ebook" = "readest.desktop";
      "application/x-fictionbook+xml" = "readest.desktop";
      "application/vnd.comicbook+zip" = "readest.desktop";
    };
  };

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
