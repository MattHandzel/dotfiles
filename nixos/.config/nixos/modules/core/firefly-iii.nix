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
  simplefinToken = "${secretsDir}/simplefin.token"; # base64 SimpleFIN Bridge SETUP token (claim URL)
  mailPassword = "${secretsDir}/mail.password"; # Gmail app password (APP_PASSWORD from the vault .env)

  # Both hostnames resolve ONLY to the Tailscale IP, so an HTTP-01 challenge can never
  # succeed. They do get a real Let's Encrypt certificate via a DNS-01 challenge against
  # Vercel (which hosts matthandzel.com's DNS) -- see security.acme.certs below. That is
  # what removes the browser's SEC_ERROR_UNKNOWN_ISSUER warning and the 502 that came
  # from HTTPS falling through to an unrelated vhost.
  fireflyUrl = "https://${domain}";
  importUrl = "https://${importDomain}";

  # VERCEL_API_TOKEN + VERCEL_TEAM_ID, consumed by lego's `vercel` DNS provider.
  acmeCredentials = "/var/lib/secrets/acme-vercel.env";

  # A failed import MUST be loud. The previous version swallowed every error and exited
  # 0, so systemd reported success for ~10 months while importing nothing.
  ntfyTopic = "http://localhost:8124/claude";

  budgetDigest = ./firefly-budget-digest.py;
in {
  services.firefly-iii = {
    enable = true;
    enableNginx = true;
    virtualHost = domain;
    settings = {
      APP_ENV = "production";
      APP_URL = fireflyUrl;
      TZ = "America/Chicago";
      DB_CONNECTION = "pgsql";
      DB_HOST = "/run/postgresql";
      DB_PORT = 5432;
      DB_DATABASE = "firefly-iii";
      DB_USERNAME = "firefly-iii";
      APP_KEY_FILE = appKeyPath;
      # NOTE: SIMPLEFIN_TOKEN deliberately does NOT belong here. Only the data importer
      # reads it (its config/simplefin.php). It lived here for ~10 months, which meant
      # the importer's SimpleFIN token was always the empty string.

      # Outbound mail, so Firefly's native notifications (bill reminders, rule-action
      # failures, security events) can actually be delivered. Gmail app password.
      MAIL_MAILER = "smtp";
      MAIL_HOST = "smtp.gmail.com";
      MAIL_PORT = 587;
      MAIL_ENCRYPTION = "tls";
      MAIL_USERNAME = "handzelmatthew@gmail.com";
      MAIL_PASSWORD_FILE = mailPassword;
      MAIL_FROM_ADDRESS = "handzelmatthew@gmail.com";
      MAIL_FROM_NAME = "Firefly III";
    };
  };

  services.nginx = {
    enable = true;
    virtualHosts.${domain} = {
      useACMEHost = domain;
      forceSSL = true;
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "handzelmatthew@gmail.com";

    # ONE certificate covering both Firefly hostnames, issued over DNS-01 so it works
    # for hosts that are only reachable inside the tailnet. Scoped deliberately to this
    # cert rather than security.acme.defaults, so other services keep their HTTP-01 flow.
    certs.${domain} = {
      domain = domain;
      extraDomainNames = [importDomain];
      dnsProvider = "vercel";
      credentialsFile = acmeCredentials;
      dnsPropagationCheck = true;
      group = "nginx";
    };
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
      FIREFLY_III_URL = fireflyUrl;
      FIREFLY_III_ACCESS_TOKEN_FILE = patFile;

      # Base64-encoded SimpleFIN Bridge SETUP token (a claim URL). Kept in a file so the
      # token stays out of git. Bridge claim tokens are SINGLE-USE: the importer only
      # exchanges it when the import config JSON has no `access_token` yet.
      SIMPLEFIN_TOKEN_FILE = simplefinToken;

      TZ = "America/Chicago";
      TRUSTED_PROXIES = "**"; # behind nginx/reverse proxy
      # Applies to the outbound call to SimpleFIN Bridge, which has a real public cert.
      VERIFY_TLS_SECURITY = "true";

      # enable POST-based automation:
      CAN_POST_AUTOIMPORT = true;
      CAN_POST_FILES = true;
      AUTO_IMPORT_SECRET_FILE = autoSecret;
      IMPORT_DIR_ALLOWLIST = importDir;
    };
  };

  # The importer shares the same certificate (it is an extraDomainName on it).
  services.nginx.virtualHosts.${importDomain} = {
    useACMEHost = domain;
    forceSSL = true;
    # A full SimpleFIN import submits every transaction to Firefly one at a time and
    # easily runs past nginx's 60s default, which returned 504 to the autoimport job
    # even though the import itself completed. Give it room.
    extraConfig = ''
      fastcgi_read_timeout 900s;
      proxy_read_timeout 900s;
      client_max_body_size 64m;
    '';
  };

  # Dirs + secrets are group-readable by `nginx`. The data importer does NOT run as
  # nginx -- it runs as uid `firefly-iii-data-importer` whose PRIMARY GROUP is nginx.
  # That is why every secret here must be 0640 and not 0600: at 0600 the importer
  # could not read the Firefly PAT, and logged "Access token is null" on every request.
  systemd.tmpfiles.rules = [
    "d ${importDir} 0750 nginx nginx -"
    "d ${secretsDir} 0750 nginx nginx -"
    "d /var/backup 0755 root root -"
    "d /var/backup/firefly 0750 postgres postgres -"
  ];

  # one-time secret init (you paste the PAT + SimpleFIN token once; autoimport secret generated)
  systemd.services."ffdi-secrets" = {
    description = "Init Firefly Importer secrets";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    # The importer's setup unit bakes these values into its cached Laravel config, so
    # the secrets must exist before it runs -- otherwise the cache pins empty strings.
    before = ["firefly-iii-data-importer-setup.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      set -eu
      umask 077
      # Firefly III Personal Access Token (Profile -> OAuth -> Personal Access Tokens):
      [ -s ${patFile} ] || echo "PLACEHOLDER_PASTE_TOKEN_HERE" > ${patFile}
      # Base64 SimpleFIN Bridge setup token (single-use claim URL):
      [ -s ${simplefinToken} ] || echo "PLACEHOLDER_PASTE_TOKEN_HERE" > ${simplefinToken}
      # Generate a 16+ char secret once. It is passed as a URL QUERY PARAMETER, so it
      # must be base64URL: a plain-base64 "+" arrives at PHP as a space and the importer
      # rejects it with "make sure your secret value matches AUTO_IMPORT_SECRET".
      gen_secret() { head -c 24 /dev/urandom | base64 | tr '+/' '-_' | tr -d '='; }
      [ -s ${autoSecret} ] || gen_secret > ${autoSecret}
      # Migrate any legacy secret containing URL-unsafe characters.
      if grep -q '[+/=]' ${autoSecret}; then
        gen_secret > ${autoSecret}
      fi
      chown nginx:nginx ${patFile} ${simplefinToken} ${autoSecret}
      chmod 0640 ${patFile} ${simplefinToken} ${autoSecret}

      # Read by Firefly III itself (user firefly-iii), NOT by the importer.
      [ -s ${mailPassword} ] || echo "PLACEHOLDER_PASTE_APP_PASSWORD_HERE" > ${mailPassword}
      chown firefly-iii:nginx ${mailPassword}
      chmod 0640 ${mailPassword}
    '';
  };

  # Daily automation: trigger importer for every JSON config in ${importDir}
  systemd.services."ffdi-autoimport" = {
    description = "Trigger Firefly Importer auto-imports";
    serviceConfig = {
      Type = "oneshot";
      User = "nginx";
    };
    path = [pkgs.curl pkgs.jq];
    script = ''
      # systemd's generated wrapper starts with `set -e`; turn it back off so a single
      # bad config alerts and continues instead of aborting the whole run silently.
      set +e
      set -uo pipefail

      alert() {
        echo "ffdi-autoimport: $1" >&2
        curl --silent --max-time 10 \
          -H "Title: Firefly import FAILED" -H "Priority: high" \
          -d "$1" "${ntfyTopic}" >/dev/null || true
      }

      token=$(cat ${patFile} 2>/dev/null)
      secret=$(cat ${autoSecret} 2>/dev/null)

      case "$token" in
        PLACEHOLDER_*|"") alert "Firefly PAT missing or unreadable (${patFile})"; exit 1 ;;
      esac
      if [ -z "$secret" ]; then
        alert "Autoimport secret missing or unreadable (${autoSecret})"
        exit 1
      fi

      shopt -s nullglob
      configs=(${importDir}/*.json)
      if [ ''${#configs[@]} -eq 0 ]; then
        alert "No import configs in ${importDir} -- nothing to import"
        exit 1
      fi

      failed=0
      for json in "''${configs[@]}"; do
        # NOTE: plain $json / $secret, NOT $${json}. Nix emits "$$" verbatim, so bash
        # read it as the PID and curl looked for a file named "<pid>{json}" --
        # "curl: (26) Failed to open/read local data" on every run since 2025-10-07.
        if curl --silent --show-error --fail \
             -H "Accept: application/json" \
             -H "Authorization: Bearer $token" \
             -F "json=@$json;type=application/json" \
             "${importUrl}/autoupload?secret=$secret"; then
          echo "ffdi-autoimport: ok $json"
        else
          failed=1
          alert "Autoimport failed for $json"
        fi
      done

      # A run that uploads the config fine but imports NOTHING still exits 0 -- that is
      # the same silent-success class that hid the 2025-10 outage for ~10 months. So do
      # not measure "did the POST succeed", measure the thing we actually care about:
      # is the newest transaction in Firefly recent? Tolerates quiet days/weekends.
      staleAfterDays=5
      newest=$(curl --silent --show-error --fail --max-time 30 \
        -H "Accept: application/json" -H "Authorization: Bearer $token" \
        "${fireflyUrl}/api/v1/transactions?limit=1&page=1" \
        | jq -r '[.data[].attributes.transactions[].date] | max // empty' | cut -dT -f1)

      if [ -z "$newest" ]; then
        alert "Could not read newest transaction from Firefly -- import health unknown"
        failed=1
      else
        ageDays=$(( ( $(date +%s) - $(date -d "$newest" +%s) ) / 86400 ))
        echo "ffdi-autoimport: newest transaction $newest ($ageDays days old)"
        if [ "$ageDays" -gt "$staleAfterDays" ]; then
          alert "Firefly has imported nothing for $ageDays days (newest txn $newest) -- the bank feed is dead"
          failed=1
        fi
      fi

      # Exit non-zero so systemd records the failure. The old script always exited 0,
      # which is why ~10 months of dead nightly runs all looked green.
      exit "$failed"
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

  # ---------- Budget digest e-mail ----------
  # Firefly has NO native budget-summary notification (only bill reminders, transaction
  # creation, rule failures and security events), so this builds one from the API.
  systemd.services."firefly-budget-digest" = {
    description = "Email Matt a Firefly budget digest";
    serviceConfig = {
      Type = "oneshot";
      User = "nginx";
    };
    path = [pkgs.python3 pkgs.curl];
    script = ''
      set +e
      exec ${pkgs.python3}/bin/python3 ${budgetDigest} \
        --pat ${patFile} --mail-password ${mailPassword} \
        --firefly-url "${fireflyUrl}" --ntfy "${ntfyTopic}" \
        --to handzelmatthew@gmail.com
    '';
  };

  systemd.timers."firefly-budget-digest" = {
    description = "Weekly + month-end Firefly budget digest";
    wantedBy = ["timers.target"];
    timerConfig = {
      # Sunday evening pace check, plus the 1st of the month for the wrap-up.
      OnCalendar = ["Sun *-*-* 18:00:00" "*-*-01 09:00:00"];
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };

  # ---------- Public category breakdown (percentages only) ----------
  # Regenerates areas/finance/firefly-category-breakdown.md from live Firefly data so
  # the website's figures track reality instead of a one-off snapshot. The script
  # normalises to percentages in memory and discards the amounts -- see the privacy
  # contract in scripts/finance/firefly-category-breakdown.py.
  systemd.services."firefly-category-breakdown" = {
    description = "Regenerate the public (percentages-only) category breakdown";
    # Runs as root because the PAT is 0640 nginx:nginx and `matth` is not in that
    # group. The generated file is handed straight back to matth so Syncthing and
    # Obsidian keep working normally.
    serviceConfig.Type = "oneshot";
    path = [pkgs.python3 pkgs.coreutils];
    script = ''
      set -uo pipefail
      out=/home/matth/Obsidian/Main/areas/finance/firefly-category-breakdown.md
      ${pkgs.python3}/bin/python3 \
        /home/matth/Obsidian/Main/scripts/finance/firefly-category-breakdown.py \
        --pat ${patFile} \
        --firefly-url "${fireflyUrl}" \
        --vault /home/matth/Obsidian/Main || exit 1
      chown matth:users "$out"
      chmod 0644 "$out"
    '';
  };

  systemd.timers."firefly-category-breakdown" = {
    description = "Refresh the public category breakdown a few times a day";
    wantedBy = ["timers.target"];
    timerConfig = {
      # systemd calendar syntax -- "04:00,10:00,16:00,22:00" is NOT valid and makes
      # systemd refuse the whole timer ("Timer unit lacks value setting").
      OnCalendar = "*-*-* 04,10,16,22:00:00";
      RandomizedDelaySec = "5m";
      Persistent = true;
    };
  };

  # ---------- Backups ----------
  # Financial history with no backup is one disk failure from gone.
  systemd.services."firefly-backup" = {
    description = "Dump the Firefly III database";
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };
    path = [pkgs.postgresql pkgs.gzip pkgs.curl];
    script = ''
      set -uo pipefail
      dir=/var/backup/firefly
      stamp=$(date +%Y-%m-%d)
      out="$dir/firefly-iii-$stamp.sql.gz"
      if ! pg_dump firefly-iii | gzip -9 > "$out"; then
        curl --silent --max-time 10 -H "Title: Firefly BACKUP FAILED" -H "Priority: high" \
          -d "pg_dump of firefly-iii failed" "${ntfyTopic}" >/dev/null || true
        exit 1
      fi
      # A zero-length or absurdly small dump is a failure that pg_dump may not report.
      size=$(stat -c %s "$out")
      if [ "$size" -lt 10000 ]; then
        curl --silent --max-time 10 -H "Title: Firefly BACKUP SUSPECT" -H "Priority: high" \
          -d "Backup $out is only $size bytes -- almost certainly truncated" "${ntfyTopic}" >/dev/null || true
        exit 1
      fi
      echo "firefly-backup: wrote $out ($size bytes)"
      # keep 30 days
      find "$dir" -name 'firefly-iii-*.sql.gz' -mtime +30 -delete
    '';
  };

  systemd.timers."firefly-backup" = {
    description = "Nightly Firefly database backup";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "02:30";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };
}
