{pkgs, ...}: {
  services.silverbullet = {
    enable = true;
    listenPort = 47000;
    listenAddress = "0.0.0.0";
    spaceDir = "/home/matth/Obsidian/Main";
    user = "matth";
    group = "users";
  };

  # Open port for Tailscale access
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 47000 ];
}
