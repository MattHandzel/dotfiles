{pkgs, ...}: let
  # MAT-1198 nameplate demo endpoint. The e-ink badge polls this for current.png + current.json.
  # The badge is NOT on Tailscale, so unlike the tailnet-only dashboard this must be reachable on
  # the LAN -> a plain-HTTP vhost on a dedicated port, opened on the host firewall. (ntfy transport
  # is WireGuard-free here; auth/abuse hardening for a PUBLIC demo is the design doc's documented
  # follow-on -- keep the topic secret and demo on a network Matt controls until then.)
  nameplatePort = 8125;
in {
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts."reading-list.matthandzel.com" = {
      forceSSL = true;
      enableACME = true;
      root = "/var/www/rss";
      locations."/" = {
        index = "feed.xml";
      };
    };

    # nameplate badge endpoint: GET /current.png (296x128 1-bit) + /current.json {hash,name,hook,contract}.
    virtualHosts."nameplate" = {
      listen = [{addr = "0.0.0.0"; port = nameplatePort;}];
      root = "/var/www/nameplate";
      locations."/" = {
        # No caching: the badge must see a new frame the instant the listener republishes. current.json
        # carries the hash so the badge can cheaply tell whether current.png actually changed.
        extraConfig = ''
          add_header Cache-Control "no-cache";
          autoindex off;
        '';
      };
    };
  };

  # Reachable on the LAN (the badge is off-tailnet). Merges with the host's existing open ports.
  networking.firewall.allowedTCPPorts = [nameplatePort];
}
