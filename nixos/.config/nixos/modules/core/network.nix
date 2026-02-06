{pkgs, ...}: {
  networking = {
    firewall.checkReversePath = true;
    networkmanager.enable = true;
    nameservers = ["1.1.1.1"];
    firewall = {
      enable = true;
      allowedTCPPorts = [22 80 443 59010 59011 8123 11434];
      allowedUDPPorts = [22 8000 59010 59011 443];
      # allowedUDPPortRanges = [
      # { from = 4000; to = 4007; }
      # { from = 8000; to = 8010; }
      # ];
    };
    extraHosts = ''
      76.191.30.233 local-server
      # 127.0.0.1 www.spotify.com # block access to spotify
      # 127.0.0.1 www.reddit.com # block access to reddit
      # 127.0.0.1 reddit.com
      # 127.0.0.1 instagram.com
      # 127.0.0.1 www.instagram.com
    '';
  };

  environment.systemPackages = with pkgs; [
    networkmanagerapplet
    openconnect
    networkmanager-openconnect

    # VPN
    wireguard-tools
    protonvpn-gui
  ];
}
