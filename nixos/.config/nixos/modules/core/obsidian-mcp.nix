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
    # Installs @bitbonsai/mcpvault + mcp-remote into a state directory on first
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

      # Install npm packages on first boot (or if they've been wiped).
      preStart = ''
        if [ ! -f ${stateDir}/node_modules/.bin/mcpvault ]; then
          ${pkgs.nodejs_22}/bin/npm install \
            @bitbonsai/mcpvault \
            mcp-remote
        fi
      '';

      script = ''
        exec ${stateDir}/node_modules/.bin/mcp-remote \
          --port ${toString port} \
          -- \
          ${stateDir}/node_modules/.bin/mcpvault \
          ${cfg.vaultPath}
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
