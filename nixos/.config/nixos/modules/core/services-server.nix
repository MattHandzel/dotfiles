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
    lidSwitchExternalPower = "ignore";
    lidSwitchDocked = "ignore";
    settings.Login = {
      IdleAction = "ignore";
      IdleActionSec = 0;
      HandlePowerKey = "poweroff";
      RuntimeDirectorySize = "10G";
    };
  };

  # Disable sleep/suspend targets entirely
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
}
