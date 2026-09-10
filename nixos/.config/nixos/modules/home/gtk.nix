# Fonts are wanted on both platforms (kitty/nvim/waybar all name JetBrainsMono
# Nerd Font, and Inter is the UI face). Everything below `gtk.*` is a GTK theme
# and a Wayland cursor theme, which have no meaning on macOS — nix-darwin
# installs fonts through `fonts.packages` instead, see modules/darwin.
{
  pkgs,
  lib,
  ...
}: {
  home.packages = [pkgs.inter];
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

  gtk = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = lib.mkForce (pkgs.catppuccin-papirus-folders.override {
        flavor = "mocha";
        accent = "lavender";
      });
    };
    theme = {
      name = "catppuccin-mocha-mauve-standard";
      package = pkgs.catppuccin-gtk.override {
        accents = ["mauve"];
        size = "standard";
        variant = "mocha";
      };
    };
    cursorTheme = {
      name = "Nordzy-cursors";
      package = pkgs.nordzy-cursor-theme;
      size = 22;
    };
  };

  home.pointerCursor = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    name = "Nordzy-cursors";
    package = pkgs.nordzy-cursor-theme;
    size = 22;
  };
}
