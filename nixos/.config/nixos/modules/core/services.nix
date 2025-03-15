{pkgs, ...}: {
  services = {
    gvfs.enable = true;
    gnome.gnome-keyring.enable = true;
    dbus.enable = true;
    fstrim.enable = true;
    printing.enable = true;
    netdata.enable = true;
    espanso.enable = true;
    avahi.enable = true;
    avahi.nssmdns4 = true;
    avahi.openFirewall = true;
  };

  services.printing.drivers = with pkgs; [gutenprint hplip brlaser];

  services.logind = {
    lidSwitch = "suspend";
    extraConfig = ''
      IdleAction=suspend
      IdleActionSec=15min
      HandlePowerKey=hibernate
      HibernateDelaySec=30m
      SuspendState=mem
    '';
  };

  virtualisation.docker.enable = true;
}
