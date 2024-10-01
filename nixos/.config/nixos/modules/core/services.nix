{...}: {
  services = {
    gvfs.enable = true;
    gnome.gnome-keyring.enable = true;
    dbus.enable = true;
    fstrim.enable = true;
    printing.enable = true;
    netdata.enable = true;
    espanso.enable = true;
  };
  services.logind = {
    lidSwitch = "suspend";
    extraConfig = ''
      IdleAction=suspend
      IdleActionSec=15min
      HandlePowerKey=suspend
    '';
  };
}
