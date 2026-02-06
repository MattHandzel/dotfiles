{pkgs, ...}: {
  services = {
    gvfs.enable = true;
    gnome.gnome-keyring.enable = true;
    dbus.enable = true;
    fstrim.enable = true;
    printing.enable = true;
    netdata.enable = true;
    espanso = {
      enable = true;
      package = pkgs.espanso-wayland;
    };
    avahi.enable = true;
    avahi.nssmdns4 = true;
    avahi.openFirewall = true;
  };

  services.printing.drivers = with pkgs; [gutenprint hplip brlaser];

  services.logind = {
    settings.Login.HandleLidSwitch = "suspend";
    # TODO: How to do this with the module?
    # extraConfig = ''
    #   IdleAction=suspend
    #   IdleActionSec=15min
    #   HandlePowerKey=suspend
    #   # HibernateDelaySec=30m
    #   SuspendState=mem
    # '';
  };

  virtualisation.docker.enable = true;
}
