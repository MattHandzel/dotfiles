{ config, lib, pkgs, ... }:

let
  cfg = config.services.obsidian-mcp;
  stateDir = "/var/lib/obsidian-mcp";
  port = 22360;
in {
  options.services.obsidian-mcp = {
    enable = lib.mkEnableOption "Obsidian vault MCP server (mcpvault over HTTP/SSE)";

    vaultPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/matth/Obsidian";
      description = "Absolute path to the Obsidian vault directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Installs @bitbonsai/mcpvault + supergateway into a state directory on first
    # start, then bridges the stdio MCP server to HTTP/SSE on port 22360.
    systemd.services.obsidian-mcp = {
      description = "Obsidian Vault MCP Server";
      after = [ "network.target" "syncthing.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = "matth";
        Group = "users";
        Restart = "on-failure";
        RestartSec = "10s";
        StateDirectory = "obsidian-mcp";
        WorkingDirectory = stateDir;
        Environment = [
          "HOME=${stateDir}"
          "npm_config_cache=${stateDir}/.npm"
        ];
      };

      path = [ pkgs.nodejs_22 ];

      # Install npm packages on first boot (or if they've been wiped). The
      # sentinel is supergateway (the new dependency) so an existing install
      # that only has the old mcp-remote gets re-provisioned.
      preStart = ''
        if [ ! -f ${stateDir}/node_modules/.bin/supergateway ]; then
          ${pkgs.nodejs_22}/bin/npm install \
            @bitbonsai/mcpvault \
            supergateway
        fi
      '';

      # supergateway runs the stdio MCP server (mcpvault) and exposes it over
      # SSE at /sse + /message on ${toString port}. mcp-remote bridges the wrong
      # direction (remote SSE -> local stdio) and treated --port as a URL.
      script = ''
        exec ${stateDir}/node_modules/.bin/supergateway \
          --stdio "${stateDir}/node_modules/.bin/mcpvault ${cfg.vaultPath}" \
          --port ${toString port}
      '';
    };

    # Expose via nginx with ACME TLS — requires DNS A record for this subdomain.
    services.nginx.virtualHosts."obsidian-mcp.matthandzel.com" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        extraConfig = ''
          proxy_read_timeout 300s;
          proxy_buffering off;
          proxy_set_header Connection "";
          proxy_http_version 1.1;
        '';
      };
    };

    # Allow access over Tailscale without going through the public internet.
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
  };
}
