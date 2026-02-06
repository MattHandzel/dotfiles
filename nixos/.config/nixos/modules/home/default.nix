{
  inputs,
  username,
  host,
  ...
}: {
  imports =
    [(import ./aseprite/aseprite.nix)] # pixel art editor
    ++ [(import ./audacious/audacious.nix)] # music player
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
    ++ [(import ./espanso.nix)] # text expander service
    ++ [(import ./scripts/scripts.nix)] # personal scripts
    # ++ [(import ./spicetify.nix)] # spotify client
    ++ [(import ./starship.nix)] # shell prompt
    ++ [(import ./swaylock.nix)] # lock screen
    ++ [(import ./vscodium.nix)] # vscode forck
    ++ [(import ./waybar)] # status bar
    ++ [(import ./zsh.nix)] # shell
    ++ [(import ./thunderbird.nix)] # thunder bird
    ++ [(import ./tmux.nix)] # terminal multiplexer
    ++ [(import ./services.nix)]
    ++ [(import ./todoist.nix)]
    ++ [inputs.catppuccin.homeModules.catppuccin]
    ++ [(import ./foliate.nix)]
    ++ [(import ./uri-handlers.nix)]
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
      "text/html" = "zen.desktop";
      "x-scheme-handler/http" = "zen.desktop";
      "x-scheme-handler/https" = "zen.desktop";
      "audio/*" = "mpv.desktop";
      "video/*" = "mpv.desktop";
      "image/*" = "feh.desktop";
      "text/css" = "nvim.desktop";
      "text/*" = "nvim.desktop";
      "application/json" = "nvim.desktop";
      "application/x-shellscript" = "nvim.desktop";
      "application/pdf" = "zathura.desktop";
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
