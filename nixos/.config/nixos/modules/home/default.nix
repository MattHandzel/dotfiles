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
    ++ [./linear-notify.nix] # poll Linear → swaync desktop notifications
    ++ [inputs.catppuccin.homeModules.catppuccin]
    ++ [(import ./foliate.nix)]
    # voice dictation (unofficial Linux AppImage port)
    ++ [./wispr-flow.nix]
    # un-stick modifiers that Wispr's uinput keyboard strands
    ++ [./stuck-key-guard.nix]
    # let Wispr see hot-plugged keyboards (the BT TOTEM) without restarting it
    ++ [./kbd-relay.nix]
    # Raycast-style command palette (SUPER+D) — launch/run/timer/calc
    ++ [./vicinae.nix]
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
      "application/pdf" = "zathura.desktop";
      # Open EPUB ebooks in Calibre's reader (not the ebook editor).
      "application/epub+zip" = "calibre-ebook-viewer.desktop";
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
