{pkgs, ...}: {
  services.nginx = {
    enable = true;
    virtualHosts."mcp.matthandzel.com" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:47771"; # Port your MCP server runs on
        proxyWebsockets = true; # Important if MCP uses WS
        extraConfig = ''
          proxy_http_version 1.1;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_set_header Host $host;
        '';
      };
    };
  };
}
