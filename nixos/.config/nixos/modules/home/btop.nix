{pkgs, ...}: {
  programs.btop = {
    enable = true;

    settings = {
      # color_theme is set by the catppuccin home module (catppuccin_mocha.theme).
      theme_background = false;
      update_ms = 500;
    };
  };

  home.packages = with pkgs; [nvtopPackages.intel];
}
