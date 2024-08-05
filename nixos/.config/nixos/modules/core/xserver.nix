{ pkgs, username, ... }: 
{
  services = {
    xserver = {
      enable = true;
      xkb.layout = "us,fr";
    };

    displayManager.autoLogin = {
      enable = true;
      user = "${username}";
    };

    libinput = {
      enable = true;
      # tapping = true;
      # naturalScrolling = false;
      # mouse = {
      #   accelProfile = "flat";
      # };
    };
  };
  # To prevent getting stuck at shutdown
  systemd.extraConfig = "DefaultTimeoutStopSec=10s";
}
