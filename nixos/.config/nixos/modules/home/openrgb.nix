{pkgs, ...}: {
  home.pkgs = with pkgs; [
    openrgb-with-all-plugins
  ];
}
