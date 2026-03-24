{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.atuin;
  dbUser = "atuin";
  dbName = "atuin";
in {
  options.services.atuin = {
    enable = lib.mkEnableOption "Enable Atuin server";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "atuin.matthandzel.com";
      description = "Domain for the Atuin server.";
    };

    openRegistration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to allow open registration for new users.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host for Atuin server to listen on.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Port for Atuin server to listen on.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. PostgreSQL Database
    services.postgresql = {
      enable = true;
      ensureDatabases = [dbName];
      ensureUsers = [{
        name = dbUser;
        ensureDBOwnership = true;
      }];
    };

    # 2. Atuin systemd service
    systemd.services.atuin-server = {
      description = "Atuin Server";
      after = ["network.target" "postgresql.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "atuin";
        Group = "atuin";
        ExecStart = "${pkgs.atuin}/bin/atuin server start";
        Restart = "on-failure";
        Environment = [
          "ATUIN_HOST=${cfg.host}"
          "ATUIN_PORT=${toString cfg.port}"
          "ATUIN_OPEN_REGISTRATION=${toString cfg.openRegistration}"
          "ATUIN_DB_URI=postgres://${dbUser}@/${dbName}?host=/run/postgresql"
        ];
      };
    };

    # 3. User and group for Atuin
    users.users.atuin = {
      isSystemUser = true;
      group = "atuin";
    };
    users.groups.atuin = {};

    # 4. Nginx reverse proxy
    services.nginx.virtualHosts.${cfg.domain} = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://${cfg.host}:${toString cfg.port}";
        proxyWebsockets = true;
        proxy_set_header = {
          Host = "$host";
          X-Real-IP = "$remote_addr";
          X-Forwarded-For = "$proxy_add_x_forwarded_for";
          X-Forwarded-Proto = "$scheme";
        };
      };
    };

    # 5. ACME for SSL
    security.acme = {
      acceptTerms = true;
      defaults.email = "handzelmatthew@gmail.com";
    };
  };
}
