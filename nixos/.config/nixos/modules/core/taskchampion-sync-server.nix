{...}: let
  port = 10222;
in {
  services.taskchampion-sync-server = {
    enable = true;
    host = "100.118.206.104";
    inherit port;
    openFirewall = false;
    allowClientIds = [
      "a3a159f0-7cb1-4359-b10c-24c3febdd722"
      "66985344-e49f-450c-b00c-f28a9024e2da"
      "0971448d-6f07-4a70-a84f-8ffc749369bd"
    ];
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [port];
}
