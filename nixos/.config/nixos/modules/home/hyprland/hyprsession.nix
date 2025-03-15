{pkgs, ...}: {
  home.packages = [pkgs.hyprlock];
  xdg.configFile."hyprsession/config.conf".text = ''
    # Your configuration here
  '';
}
