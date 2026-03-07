{pkgs, ...}: {
  services = {
    dbus.enable = true;
    fstrim.enable = true;
    netdata.enable = true;
    avahi.enable = true;
    avahi.nssmdns4 = true;
    avahi.openFirewall = true;
    
    # Remote desktop might be useful via SSH, but for headless we usually disable GUI services
    gvfs.enable = false;
    gnome.gnome-keyring.enable = false;
    printing.enable = false;
    espanso.enable = false;
  };

  services.logind = {
    lidSwitch = "ignore";
    settings.Login = {
      IdleAction = "ignore";
      HandlePowerKey = "poweroff";
    };
  };
}
