{pkgs, ...}: {
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
  };
}
