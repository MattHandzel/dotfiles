{
  pkgs,
  config,
  ...
}: {
  fonts.fontconfig.enable = true;
  # home.packages = [
  #   pkgs.nerd-fonts
  #   pkgs.nerd-fonts.jetbrains-mono
  #   pkgs.nerd-fonts.noto
  #   pkgs.twemoji-color-font
  #   pkgs.noto-fonts-emoji
  #   pkgs.corefonts
  #   pkgs.noto-fonts
  # ];

  gtk = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.catppuccin-papirus-folders.override {
        flavor = "mocha";
        accent = "lavender";
      };
    };
    theme = {
      name = "Dracula";
      package = pkgs.dracula-theme;
    };
    cursorTheme = {
      name = "Nordzy-cursors";
      package = pkgs.nordzy-cursor-theme;
      size = 22;
    };
  };

  home.pointerCursor = {
    name = "Nordzy-cursors";
    package = pkgs.nordzy-cursor-theme;
    size = 22;
  };
}
