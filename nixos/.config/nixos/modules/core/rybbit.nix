# rybbit.nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  domain = "analytics.matthandzel.com"; # adjust to your public hostname

  # Persistent layout
  stateDir = "/var/lib/rybbit";
  dataDir = "${stateDir}/data";
  envDir = "${stateDir}/env";
  secretsDir = "${stateDir}/secrets";

  # Generated env files
  backendEnvFile = "${envDir}/backend.env";
  clientEnvFile = "${envDir}/client.env";
  postgresEnvFile = "${envDir}/postgres.env";
  clickhouseEnvFile = "${envDir}/clickhouse.env";

  # Secrets (generated on first boot; override with your own if desired)
  betterAuthSecretFile = "${secretsDir}/better-auth-secret";
  postgresPasswordFile = "${secretsDir}/postgres-password";
  clickhousePasswordFile = "${secretsDir}/clickhouse-password";
  mapboxTokenFile = "${secretsDir}/mapbox-token"; # optional, leave empty to skip

  # Container images (pin as needed)
  backendImage = "ghcr.io/rybbit/rybbit-backend:latest";
  clientImage = "ghcr.io/rybbit/rybbit-client:latest";
  postgresImage = "postgres:16-alpine";
  clickhouseImage = "clickhouse/clickhouse-server:latest";
in {
  systemd.tmpfiles.rules =
    [
      "d ${stateDir} 0750 root root -"
      "d ${dataDir} 0750 root root -"
      "d ${envDir} 0750 root root -"
      "d ${secretsDir} 0750 root root -"
      "d ${dataDir}/postgres 0750 root root -"
      "d ${dataDir}/clickhouse 0750 root root -"
    ];

  systemd.services."rybbit-secrets" = {
    description = "Initialize Rybbit secrets";
    wantedBy = ["multi-user.target"];
    before = [
      "docker-rybbit-backend.service"
      "docker-rybbit-client.service"
      "docker-rybbit-postgres.service"
      "docker-rybbit-clickhouse.service"
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      umask 077
      mkdir -p ${secretsDir}

      if [ ! -s ${betterAuthSecretFile} ]; then
        head -c 32 /dev/urandom | base64 | tr -d '\n' > ${betterAuthSecretFile}
      fi

      if [ ! -s ${postgresPasswordFile} ]; then
        head -c 32 /dev/urandom | base64 | tr -d '\n' > ${postgresPasswordFile}
      fi

      if [ ! -s ${clickhousePasswordFile} ]; then
        head -c 32 /dev/urandom | base64 | tr -d '\n' > ${clickhousePasswordFile}
      fi

      if [ ! -e ${mapboxTokenFile} ]; then
        touch ${mapboxTokenFile}
      fi
    '';
  };

  systemd.services."rybbit-env" = {
    description = "Generate env files for Rybbit containers";
    wantedBy = ["multi-user.target"];
    after = ["rybbit-secrets.service"];
    before = [
      "docker-rybbit-backend.service"
      "docker-rybbit-client.service"
      "docker-rybbit-postgres.service"
      "docker-rybbit-clickhouse.service"
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      umask 077
      mkdir -p ${envDir}

      better_auth=$(tr -d '\n' < ${betterAuthSecretFile})
      pg_pass=$(tr -d '\n' < ${postgresPasswordFile})
      ch_pass=$(tr -d '\n' < ${clickhousePasswordFile})

      mapbox_token=""
      if [ -s ${mapboxTokenFile} ]; then
        mapbox_token=$(tr -d '\n' < ${mapboxTokenFile})
      fi

      cat > ${backendEnvFile} <<EOF
DOMAIN_NAME=${domain}
BASE_URL=https://${domain}
DISABLE_SIGNUP=false
DISABLE_AUTONOMOUS_TELEMETRY=true
BETTER_AUTH_SECRET=$better_auth
POSTGRES_HOST=rybbit-postgres
POSTGRES_PORT=5432
POSTGRES_DB=analytics
POSTGRES_USER=frog
POSTGRES_PASSWORD=$pg_pass
CLICKHOUSE_HOST=rybbit-clickhouse
CLICKHOUSE_PORT=8123
CLICKHOUSE_DB=analytics
CLICKHOUSE_USER=frog
CLICKHOUSE_PASSWORD=$ch_pass
EOF

      if [ -n "$mapbox_token" ]; then
        printf 'MAPBOX_TOKEN=%s\n' "$mapbox_token" >> ${backendEnvFile}
      fi

      cat > ${clientEnvFile} <<EOF
RYBBIT_PUBLIC_BASE_URL=https://${domain}
RYBBIT_PUBLIC_API_URL=https://${domain}/api
DISABLE_AUTONOMOUS_TELEMETRY=true
EOF

      if [ -n "$mapbox_token" ]; then
        printf 'NEXT_PUBLIC_MAPBOX_TOKEN=%s\n' "$mapbox_token" >> ${clientEnvFile}
      fi

      cat > ${postgresEnvFile} <<EOF
POSTGRES_DB=analytics
POSTGRES_USER=frog
POSTGRES_PASSWORD=$pg_pass
EOF

      cat > ${clickhouseEnvFile} <<EOF
CLICKHOUSE_DB=analytics
CLICKHOUSE_USER=frog
CLICKHOUSE_PASSWORD=$ch_pass
EOF
    '';
  };

  # Ensure container units wait for env/secrets
  systemd.services."docker-rybbit-postgres" = {
    after = ["rybbit-env.service"];
    requires = ["rybbit-env.service"];
  };
  systemd.services."docker-rybbit-clickhouse" = {
    after = ["rybbit-env.service"];
    requires = ["rybbit-env.service"];
  };
  systemd.services."docker-rybbit-backend" = {
    after = [
      "docker-rybbit-postgres.service"
      "docker-rybbit-clickhouse.service"
      "rybbit-env.service"
    ];
    requires = [
      "docker-rybbit-postgres.service"
      "docker-rybbit-clickhouse.service"
      "rybbit-env.service"
    ];
  };
  systemd.services."docker-rybbit-client" = {
    after = [
      "docker-rybbit-backend.service"
      "rybbit-env.service"
    ];
    requires = [
      "docker-rybbit-backend.service"
      "rybbit-env.service"
    ];
  };

  virtualisation.oci-containers.containers = {
    rybbit-postgres = {
      autoStart = true;
      image = postgresImage;
      environmentFiles = [postgresEnvFile];
      volumes = [
        "${dataDir}/postgres:/var/lib/postgresql/data"
      ];
    };

    rybbit-clickhouse = {
      autoStart = true;
      image = clickhouseImage;
      environmentFiles = [clickhouseEnvFile];
      volumes = [
        "${dataDir}/clickhouse:/var/lib/clickhouse"
      ];
    };

    rybbit-backend = {
      autoStart = true;
      image = backendImage;
      environmentFiles = [backendEnvFile];
      ports = ["127.0.0.1:3001:3001"];
    };

    rybbit-client = {
      autoStart = true;
      image = clientImage;
      environmentFiles = [clientEnvFile];
      ports = ["127.0.0.1:3002:3002"];
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.${domain} = {
      forceSSL = true;
      enableACME = true;
      extraConfig = ''
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;
        add_header Permissions-Policy "geolocation=()" always;
      '';
      locations = {
        "/api/" = {
          proxyPass = "http://127.0.0.1:3001/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
        "/" = {
          proxyPass = "http://127.0.0.1:3002/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
          '';
        };
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "handzelmatthew@gmail.com";
  };
}
