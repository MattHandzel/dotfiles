{pkgs, ...}: {
  programs.thunderbird = {
    enable = true;
    profiles = {
      matth = {
        isDefault = true;
        # profileDir = "/home/matth/.thunderbird/"; # This is the default location
        # profileDir = "/home/matth/.mozilla-thunderbird/"; # This is the default location for some distributions
        settings = {
          "network.dns.disableIPv6" = true;
        };
      }; # c8ym09yb
    };
  };
}
