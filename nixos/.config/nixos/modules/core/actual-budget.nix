{...}: let
  # Actual Budget -- self-hosted envelope budgeting (https://actualbudget.org).
  #
  # Added alongside Firefly III rather than replacing it: Firefly stays the
  # system of record until Actual has proven itself on real data. The two do not
  # share a database, so running both is safe.
  #
  # Why it is here at all: Firefly's real weakness for Matt is not the ledger, it
  # is (a) budgeting ergonomics and (b) investments. Actual fixes the first.
  # Ghostfolio (modules/core/ghostfolio.nix) fixes the second.
  #
  # Actual speaks SimpleFIN natively, so it can reuse the SAME SimpleFIN token
  # already used by the Firefly data importer -- the token is entered through
  # Actual's own UI (Settings -> Bank Sync), NOT baked in here, because SimpleFIN
  # setup tokens are single-use and live in /var/lib/firefly-iii/secrets.
  #
  # Tailnet-only, same convention as firefly-pico.nix: no public hostname and no
  # certificate, so this never chains onto the ACME/DNS-01 work.
  #   http://matts-server.tail01a272.ts.net:5006
  tailnetIP = "100.118.206.104";
  port = 5006;
in {
  services.actual = {
    enable = true;
    settings = {
      # Bind to the tailnet address only -- never 0.0.0.0.
      hostname = tailnetIP;
      inherit port;
    };
  };

  # Native service (not a container), so the NixOS firewall applies and the port
  # must be opened explicitly on the tailnet interface -- same as silverbullet.nix.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [port];
}
