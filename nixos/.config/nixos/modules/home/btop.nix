{
  lib,
  pkgs,
  ...
}: {
  programs.btop = {
    enable = true;

    settings = {
      # color_theme is set by the catppuccin home module (catppuccin_mocha.theme).
      theme_background = false;
      update_ms = 500;
    };
  };

  # nvtop's Intel backend reads /sys/class/drm — Linux-only by construction, and
  # the Mac's GPU is Apple silicon anyway (btop itself reports it there).
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.nvtopPackages.intel];
}
