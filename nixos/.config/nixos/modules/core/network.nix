{pkgs, ...}: {
  networking = {
    hostName = "matts-computer";
    networkmanager.enable = true;
    nameservers = ["1.1.1.1"];
    firewall = {
      enable = true;
      allowedTCPPorts = [22 80 443 59010 59011 8123];
      allowedUDPPorts = [59010 59011];
      # allowedUDPPortRanges = [
      # { from = 4000; to = 4007; }
      # { from = 8000; to = 8010; }
      # ];
    };
    extraHosts = ''
      76.191.29.250 local-server
      messages.google.com wiadomosci
    '';
  };

  environment.systemPackages = with pkgs; [
    networkmanagerapplet
  ];
}
