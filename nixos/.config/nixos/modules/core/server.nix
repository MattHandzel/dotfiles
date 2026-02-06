{
  inputs,
  nixpkgs,
  self,
  username,
  host,
  ...
}: {
  imports = [
    (import ./bootloader.nix)
    (import ./hardware.nix)
    (import ./network.nix)
    (import ./program.nix)
    (import ./security.nix)
    (import ./services-server.nix)
    (import ./system.nix)
    (import ./user.nix)
    (import ./virtualization-server.nix)
    (import ./firefly-iii.nix)
    (import ./freshrss.nix)
    (import ./mcp-server.nix)
    (import ./nginx.nix)
    # (import ./tor.nix) # Uncomment if you need Tor on the server
  ];

  # Server-specific overrides
  services.printing.enable = false; # Usually not needed for remote servers
  
  # Ensure we have SSH enabled (though it's often in hosts/server/default.nix too)
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true; # Adjust based on your preference
    settings.PermitRootLogin = "no";
  };

  # Graphics might be needed for CUDA/transcription, keeping it enabled in hardware.nix
}
