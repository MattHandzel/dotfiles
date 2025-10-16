# freshrss.nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  domain = "rss.matthandzel.com"; # <-- set your domain
  stateDir = "/var/lib/freshrss"; # data dir (owned/managed by the module)
  secretFile = "/run/secrets/freshrss-admin"; # create via systemd-tmpfiles or sops-nix
in {
  # --- FreshRSS core ---
  services.freshrss = {
    enable = true;

    # Use nixpkgs' packaged FreshRSS
    # package = pkgs.freshrss;  # (optional override)

    # Web integration
    webserver = "nginx"; # "nginx" | "caddy"
    virtualHost = domain; # vhost name for your chosen webserver
    baseUrl = "https://${domain}";
    language = "en";

    # First admin user
    defaultUser = "admin";
    passwordFile = secretFile;

    # Data & DB
    dataDir = stateDir;

    # Simple & reliable for single-user/small installs
    database = {
      type = "sqlite"; # alternatives: "pgsql" or "mysql"
      # host = "localhost";  # not used for sqlite
      # name = "freshrss";   # not used for sqlite
      # user = "freshrss";   # not used for sqlite
      # passFile = "/run/secrets/freshrss-db";  # not used for sqlite
    };

    # Optional: initial auth type if you want to disable the setup wizard
    # authType = "form";   # or "none" if you want to skip auth (not recommended)
  };

  # --- Web server (nginx) with ACME ---
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts.${domain} = {
      enableACME = true;
      forceSSL = true;
      # No need to define PHP locations: the FreshRSS module wires php-fpm for you
    };
  };

  # --- Secrets: simple tmpfiles stub (replace with sops-nix if you prefer) ---
  systemd.tmpfiles.rules = [
    "d /run/secrets 0750 root root -"
    # Replace 'SuperSecret' with your actual admin password before first switch.
    "w ${secretFile} 0640 root root - - SuperSecret"
  ];

  # --- Harden PHP-FPM via module defaults (FreshRSS module already sets up pools) ---
  # If you need custom php.ini flags, you can extend phpOptions here:
  # services.phpfpm.pools.freshrss.phpOptions = ''
  #   upload_max_filesize = 32M
  #   post_max_size = 32M
  # '';

  # --- OPTIONAL: PostgreSQL configuration (uncomment to use pgsql) ---
  # services.freshrss.database = {
  #   type = "pgsql";
  #   host = "localhost";
  #   name = "freshrss";
  #   user = "freshrss";
  #   passFile = "/run/secrets/freshrss-db";
  # };
  #
  # services.postgresql = {
  #   enable = true;
  #   ensureDatabases = [ "freshrss" ];
  #   ensureUsers = [{
  #     name = "freshrss";
  #     ensureDBOwnership = true;
  #     # Or grant privileges explicitly:
  #     # ensurePermissions = { "DATABASE freshrss" = "ALL PRIVILEGES"; };
  #   }];
  # };
  #
  # systemd.tmpfiles.rules = [
  #   "d /run/secrets 0750 root root -"
  #   "w /run/secrets/freshrss-db 0640 root root - - ChangeMe_DB_Pass"
  # ];
}
