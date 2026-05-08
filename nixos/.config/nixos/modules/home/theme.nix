{lib, ...}: {
  options.theme = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "catppuccin-mocha";
      description = "Active theme preset name. Used by modules that take a named theme attr (e.g. starship, btop).";
    };

    palette = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "Palette as 6-char hex strings without leading '#'. Callers prepend '#' or wrap in rgb()/rgba() as needed.";
    };

    font = {
      ui = lib.mkOption {
        type = lib.types.str;
        default = "JetBrainsMono Nerd Font";
      };
      mono = lib.mkOption {
        type = lib.types.str;
        default = "JetBrainsMono Nerd Font";
      };
      sizes = lib.mkOption {
        type = lib.types.attrsOf lib.types.int;
        default = {
          xs = 10;
          sm = 11;
          md = 13;
          lg = 15;
          xl = 20;
          huge = 110;
        };
      };
    };

    radius = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };
    border = lib.mkOption {
      type = lib.types.int;
      default = 2;
    };
    opacity = lib.mkOption {
      type = lib.types.float;
      default = 0.98;
    };
  };

  # Catppuccin Mocha — https://catppuccin.com/palette/
  config.theme.palette = {
    rosewater = "f5e0dc";
    flamingo = "f2cdcd";
    pink = "f5c2e7";
    mauve = "cba6f7";
    red = "f38ba8";
    maroon = "eba0ac";
    peach = "fab387";
    yellow = "f9e2af";
    green = "a6e3a1";
    teal = "94e2d5";
    sky = "89dceb";
    sapphire = "74c7ec";
    blue = "89b4fa";
    lavender = "b4befe";
    text = "cdd6f4";
    subtext1 = "bac2de";
    subtext0 = "a6adc8";
    overlay2 = "9399b2";
    overlay1 = "7f849c";
    overlay0 = "6c7086";
    surface2 = "585b70";
    surface1 = "45475a";
    surface0 = "313244";
    base = "1e1e2e";
    mantle = "181825";
    crust = "11111b";
  };
}
