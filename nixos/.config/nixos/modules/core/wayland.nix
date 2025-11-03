{
  inputs,
  pkgs,
  ...
}: {
  programs.hyprland.enable = true;
  programs.hyprland.package = pkgs.hyprland;
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    xdgOpenUsePortal = true;
    extraPortals = [
      # pkgs.xdg-desktop-portal-kde
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
  };

  environment.systemPackages = with pkgs; [
    mesa
    libglvnd
  ];
}
