{
  lib,
  pkgs,
  config,
  ...
}: let
  appKeyPath = "/var/lib/firefly-iii/secrets/app.key";

  # your existing Firefly host:
  domain = "firefly.matthandzel.com";
  # new importer host:
  importDomain = "import.firefly.matthandzel.com";

  secretsDir = "/var/lib/firefly-iii/secrets";
  importDir = "/var/lib/firefly-iii/import";

  patFile = "${secretsDir}/importer.pat"; # Firefly PAT
  autoSecret = "${secretsDir}/autoimport.secret"; # >=16 chars, used by FFDI POST API
in {
  services.firefly-iii = {
    enable = true;
    enableNginx = true;
    virtualHost = domain;
    settings = {
      APP_ENV = "production";
      APP_URL = "https://${domain}";
      TZ = "America/Chicago";
      DB_CONNECTION = "pgsql";
      DB_HOST = "/run/postgresql";
      DB_PORT = 5432;
      DB_DATABASE = "firefly-iii";
      DB_USERNAME = "firefly-iii";
      APP_KEY_FILE = appKeyPath;
      SIMPLEFIN_TOKEN = "aHR0cHM6Ly9iZXRhLWJyaWRnZS5zaW1wbGVmaW4ub3JnL3NpbXBsZWZpbi9jbGFpbS8zODZCMEUzMkE0RDgxRTg1Q0EwNUI5NDVCN0JGRThERDYyMzI4RkM3QjM5NUQ4ODk2RjRFRjJFMzVCNjdDMkIzNEQyQTVCNUI0MkE2NzQzRDUxRDkyQTAwQzgwRDkwNTMyQzM3QTgzNzZCMDUxNUVBMDVFRDgwQjdDNThGNTNCNw==";
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.${domain} = {
      enableACME = true; # automatically gets a TLS certificate
      forceSSL = true; # redirect http → https
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "handzelmatthew@gmail.com";
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = ["firefly-iii"];
    ensureUsers = [
      {
        name = "firefly-iii";
        ensureDBOwnership = true;
      }
    ];
  };

  users.users.firefly-iii = {isSystemUser = true;};
  users.groups.firefly-iii = {};
  systemd.services."firefly-iii-generate-app-key" = {
    description = "Generate Firefly III APP_KEY";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      f='${appKeyPath}'
      if [ ! -s "$f" ]; then
        umask 077
        printf "base64:%s\n" "$(head -c 32 /dev/urandom | base64)" > "$f"
        chown firefly-iii:firefly-iii "$f"
      fi
    '';
  };

  # ---------- Firefly III Data Importer ----------
  services.firefly-iii-data-importer = {
    enable = true;
    enableNginx = true;
    virtualHost = importDomain;

    # Maps 1:1 to FFDI .env vars (supports *_FILE for secrets).
    # See .env.example for these exact names.
    settings = {
      FIREFLY_III_URL = "https://${domain}";
      FIREFLY_III_ACCESS_TOKEN_FILE = patFile;

      TZ = "America/Chicago";
      TRUSTED_PROXIES = "**"; # behind nginx/reverse proxy
      VERIFY_TLS_SECURITY = "true";

      # enable POST-based automation:
      CAN_POST_AUTOIMPORT = true;
      CAN_POST_FILES = true;
      AUTO_IMPORT_SECRET_FILE = autoSecret;
      IMPORT_DIR_ALLOWLIST = importDir;
    };
  };

  # Public HTTPS for importer too
  services.nginx.virtualHosts.${importDomain} = {
    enableACME = true;
    forceSSL = true;
  };

  # dirs + secrets, owned by nginx (FFDI runs under nginx/php-fpm)
  systemd.tmpfiles.rules = [
    "d ${importDir} 0750 nginx nginx -"
    "d ${secretsDir} 0750 nginx nginx -"
  ];

  # one-time secret init (you'll paste the PAT once; autoimport secret generated)
  systemd.services."ffdi-secrets" = {
    description = "Init Firefly Importer secrets";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      umask 077
      # Put your Firefly Personal Access Token in this file (see step 2 below):
      [ -s ${patFile} ] || (echo "PLACEHOLDER_PASTE_TOKEN_HERE" > ${patFile})
      # Generate a 16+ char secret once:
      [ -s ${autoSecret} ] || head -c 24 /dev/urandom | base64 > ${autoSecret}
      chown nginx:nginx ${patFile} ${autoSecret}
    '';
  };

  # Daily automation: trigger importer for every JSON config in ${importDir}
  systemd.services."ffdi-autoimport" = {
    description = "Trigger Firefly Importer auto-imports";
    serviceConfig = {
      Type = "oneshot";
      User = "nginx";
    };
    path = [pkgs.curl];
    script = ''
      set -euo pipefail
      token=$(cat ${patFile})
      secret=$(cat ${autoSecret})
      for json in ${importDir}/*.json; do
        [ -f "$json" ] || continue
        curl --silent --show-error --fail \
          -H "Accept: application/json" \
          -H "Authorization: Bearer $token" \
          -F "json=@$${json};type=application/json" \
          "https://${importDomain}/autoupload?secret=$${secret}" \
          || echo "Autoimport failed for $json" >&2
      done
    '';
  };

  systemd.timers."ffdi-autoimport" = {
    description = "Nightly Firefly imports";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "03:15";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };
}
