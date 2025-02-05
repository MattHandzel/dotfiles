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
    # ++ [(import ./notion.nix)]
    # ++ [(import ./ntfy.nix)]
    ;

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = "yazi.desktop";
      "text/plain" = "nvim.desktop";
      "text/x-python" = "nvim.desktop";
    };
  };

  home.sessionVariables = {
    TERMINAL = "kitty";
  };
}
