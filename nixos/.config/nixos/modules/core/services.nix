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

  services.logind.settings = {
    Login = {
      HandlePowerKey = "suspend";
      SuspendState = "mem";
      HandleLidSwitch = "suspend";
      IdleAction = "suspend";
      IdleActionSec = "15min";
    };
  };

  virtualisation.docker.enable = true;
}
