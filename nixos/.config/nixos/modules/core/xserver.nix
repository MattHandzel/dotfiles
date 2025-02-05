{
  pkgs,
  username,
  ...
}: {
  environment.systemPackages = with pkgs; [
    libinput
  ];
  services = {
    xserver = {
      enable = true;
      xkb.layout = "us";
      xkb.options = "fn:fnmode";
      exportConfiguration = true;
    };

    displayManager.autoLogin = {
      enable = true;
      user = "${username}";
    };
    libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
        tapping = true;
        scrollMethod = "twofinger";
        middleEmulation = true;
        disableWhileTyping = true;
      };
      # keyboard = {
      #   options = "fk:2";
      #
      #         };
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
