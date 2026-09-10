{
  config,
  pkgs,
  lib,
  ...
}: let
  # Prometheus + Grafana + the Firefly III exporter.
  #
  # These are two DIFFERENT things that work as a pair:
  #   Prometheus -- time-series database. Scrapes numbers on a schedule and stores
  #                 them with history. No real UI to speak of.
  #   Grafana    -- the dashboard layer. Queries Prometheus and draws the graphs.
  #
  # Bound to the tailnet address only -- never 0.0.0.0. Grafana has no public
  # exposure and no anonymous access.
  tailnetIP = "100.118.206.104";

  prometheusPort = 9090;
  grafanaPort = 3001; # 3000 avoided: inbox-zero's web container already uses it
  fireflyExporterPort = 9995;

  # The exporter wants FIREFLY_III_TOKEN in its environment. The PAT lives in a file,
  # so it is handed over as an env-file rather than being written into the Nix store
  # (anything in `environment` above is world-readable in /nix/store).
  fireflyExporterEnv = "/var/lib/secrets/firefly-exporter.env";
  grafanaSecretKey = "/var/lib/secrets/grafana-secret-key";
in {
  # ---------- Firefly III exporter ----------
  # https://github.com/kinduff/firefly_iii_exporter
  # Exposes account balances, transaction and category counts as Prometheus metrics,
  # which is what makes "net worth over time" graphable -- Firefly itself only ever
  # shows you the present moment.
  virtualisation.oci-containers.containers."firefly-exporter" = {
    # Note the UNDERSCORES -- ghcr.io/kinduff/firefly-iii-exporter (hyphens) does not
    # exist and the registry answers "denied", which looks like an auth problem but is
    # really a 404. Env vars are BASE_URL/API_KEY and the port is 4002, not 8000.
    image = "kinduff/firefly_iii_exporter:latest";
    autoStart = true;
    ports = ["127.0.0.1:${toString fireflyExporterPort}:4002"];
    environment = {
      BASE_URL = "https://firefly.matthandzel.com";
    };
    environmentFiles = [fireflyExporterEnv];
  };

  # Generate the secrets this module needs, so nothing sensitive lives in the flake.
  # The exporter env-file is seeded with the Firefly PAT that already exists on disk.
  # 0755 so unprivileged services can TRAVERSE into it -- at 0700 Grafana could not
  # even stat its own key file and died with "permission denied". The files inside
  # are individually 0400 and owned by their consumer, so nothing is exposed.
  systemd.tmpfiles.rules = ["d /var/lib/secrets 0755 root root -"];

  systemd.services."monitoring-secrets" = {
    description = "Generate Grafana secret key + Firefly exporter env";
    wantedBy = ["multi-user.target"];
    before = ["grafana.service" "docker-firefly-exporter.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      umask 077
      # Grafana's file provider reads the RAW key from this file -- no KEY=value.
      if [ ! -s ${grafanaSecretKey} ]; then
        head -c 32 /dev/urandom | base64 | tr -d '\n' > ${grafanaSecretKey}
      fi
      chmod 0400 ${grafanaSecretKey}
      chown grafana:grafana ${grafanaSecretKey} 2>/dev/null || true

      if [ -s /var/lib/firefly-iii/secrets/importer.pat ]; then
        printf 'API_KEY=%s\n' "$(cat /var/lib/firefly-iii/secrets/importer.pat)" > ${fireflyExporterEnv}
        chmod 0400 ${fireflyExporterEnv}
      fi
    '';
  };

  services.prometheus = {
    enable = true;
    port = prometheusPort;
    listenAddress = tailnetIP;
    retentionTime = "365d"; # a year of history -- this is the whole point
    globalConfig.scrape_interval = "60s";
    scrapeConfigs = [
      {
        job_name = "firefly";
        static_configs = [{targets = ["127.0.0.1:${toString fireflyExporterPort}"];}];
        # Balances change slowly and each scrape hits the Firefly API.
        scrape_interval = "15m";
      }
      {
        job_name = "node";
        static_configs = [{targets = ["127.0.0.1:9100"];}];
      }
    ];
  };

  # Host metrics, so the box itself is graphable too.
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9100;
    enabledCollectors = ["systemd" "processes"];
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = tailnetIP;
        http_port = grafanaPort;
        root_url = "http://${tailnetIP}:${toString grafanaPort}/";
      };
      security.admin_user = "matth";
      # Grafana's own "file provider" syntax. The key is generated on the box by
      # monitoring-secrets.service, so it never enters the world-readable Nix store.
      security.secret_key = "$__file{${grafanaSecretKey}}";
      # Grafana generates its own admin password on first run; change it in the UI.
      "auth.anonymous".enabled = false;
      analytics.reporting_enabled = false;
    };
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://${tailnetIP}:${toString prometheusPort}";
          isDefault = true;
        }
      ];
    };
  };
}
