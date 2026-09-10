{pkgs, ...}: let
  # Ghostfolio -- self-hosted portfolio / net-worth tracker
  # (https://github.com/ghostfolio/ghostfolio, AGPL-3.0).
  #
  # This exists because Firefly III is double-entry bookkeeping with no concept of
  # holdings, lots or cost basis. Matt's Schwab Individual + two Roth IRAs are
  # therefore imported as ordinary transactions, which is why tickers (NVIDIA,
  # META, SPDR, APPLE...) currently appear as BOTH revenue and expense accounts in
  # Firefly and pollute every income/expense report. Ghostfolio is the right tool
  # for that half; Firefly keeps the cash ledger.
  #
  # Run as containers rather than pkgs.ghostfolio: the upstream image runs its
  # Prisma migrations on boot, which the bare package does not. The server already
  # uses oci-containers for every other service of this shape (rybbit, firefly-pico,
  # kokoro-tts), so this stays consistent with the rest of the host.
  #
  # Postgres and Redis are DEDICATED to Ghostfolio and deliberately not the
  # existing firefly-iii Postgres -- a schema mistake here must never be able to
  # touch the financial database.
  #
  # Tailnet-only, same convention as firefly-pico.nix (docker publishes straight to
  # the tailnet IP, bypassing the NixOS firewall, so no firewall rule is needed).
  #   http://matts-server.tail01a272.ts.net:3333
  tailnetIP = "100.118.206.104";
  port = 3333;

  stateDir = "/var/lib/ghostfolio";
  secretsDir = "${stateDir}/secrets";
  envDir = "${stateDir}/env";

  appEnvFile = "${envDir}/app.env";
  postgresEnvFile = "${envDir}/postgres.env";

  pgPasswordFile = "${secretsDir}/postgres.password";
  accessTokenSaltFile = "${secretsDir}/access-token.salt";
  jwtSecretFile = "${secretsDir}/jwt.secret";
  redisPasswordFile = "${secretsDir}/redis.password";

  # Pinned, not `latest`: an image that silently rolls forward under a finance app
  # is how you get a migration you did not ask for.
  ghostfolioImage = "ghostfolio/ghostfolio:2.239.0";
  postgresImage = "postgres:16-alpine";
  redisImage = "redis:7-alpine";

  network = "ghostfolio";

  dbName = "ghostfolio";
  dbUser = "ghostfolio";
in {
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
    "d ${stateDir}/postgres 0750 root root -"
    "d ${secretsDir} 0700 root root -"
    "d ${envDir} 0700 root root -"
  ];

  # One-time secret generation. Every value is generated locally and never leaves
  # the box; nothing here is in git.
  systemd.services."ghostfolio-secrets" = {
    description = "Generate Ghostfolio secrets";
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "oneshot";
    path = [pkgs.openssl pkgs.coreutils];
    script = ''
      set -eu
      umask 077
      mkdir -p ${secretsDir}
      for f in ${pgPasswordFile} ${accessTokenSaltFile} ${jwtSecretFile} ${redisPasswordFile}; do
        if [ ! -s "$f" ]; then
          openssl rand -hex 32 > "$f"
        fi
        chmod 0600 "$f"
      done
    '';
  };

  # Render the env files the containers consume.
  systemd.services."ghostfolio-env" = {
    description = "Generate env files for Ghostfolio containers";
    wantedBy = ["multi-user.target"];
    after = ["ghostfolio-secrets.service"];
    requires = ["ghostfolio-secrets.service"];
    before = [
      "docker-ghostfolio.service"
      "docker-ghostfolio-postgres.service"
      "docker-ghostfolio-redis.service"
    ];
    serviceConfig.Type = "oneshot";
    path = [pkgs.coreutils];
    script = ''
            set -eu
            umask 077
            mkdir -p ${envDir}

            pg_pass=$(tr -d '\n' < ${pgPasswordFile})
            salt=$(tr -d '\n' < ${accessTokenSaltFile})
            jwt=$(tr -d '\n' < ${jwtSecretFile})
            redis_pass=$(tr -d '\n' < ${redisPasswordFile})

            cat > ${postgresEnvFile} <<EOF
      POSTGRES_DB=${dbName}
      POSTGRES_USER=${dbUser}
      POSTGRES_PASSWORD=$pg_pass
      EOF

            cat > ${appEnvFile} <<EOF
      NODE_ENV=production
      PORT=3333
      DATABASE_URL=postgresql://${dbUser}:$pg_pass@ghostfolio-postgres:5432/${dbName}?connect_timeout=300&sslmode=prefer
      ACCESS_TOKEN_SALT=$salt
      JWT_SECRET_KEY=$jwt
      REDIS_HOST=ghostfolio-redis
      REDIS_PORT=6379
      REDIS_PASSWORD=$redis_pass
      EOF

            chmod 0600 ${postgresEnvFile} ${appEnvFile}
    '';
  };

  # oci-containers does not create user-defined docker networks, and the default
  # bridge does NOT resolve container names -- so DATABASE_URL's
  # `@ghostfolio-postgres` would never resolve without this.
  systemd.services."ghostfolio-network" = {
    description = "Create the Ghostfolio docker network";
    wantedBy = ["multi-user.target"];
    after = ["docker.service"];
    requires = ["docker.service"];
    before = [
      "docker-ghostfolio.service"
      "docker-ghostfolio-postgres.service"
      "docker-ghostfolio-redis.service"
    ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      ${pkgs.docker}/bin/docker network inspect ${network} >/dev/null 2>&1 \
        || ${pkgs.docker}/bin/docker network create ${network}
    '';
  };

  # The app must not start before its database and cache exist.
  systemd.services."docker-ghostfolio" = {
    after = [
      "docker-ghostfolio-postgres.service"
      "docker-ghostfolio-redis.service"
      "ghostfolio-env.service"
      "ghostfolio-network.service"
    ];
    requires = [
      "docker-ghostfolio-postgres.service"
      "docker-ghostfolio-redis.service"
      "ghostfolio-env.service"
      "ghostfolio-network.service"
    ];
  };

  virtualisation.oci-containers.containers = {
    ghostfolio-postgres = {
      autoStart = true;
      image = postgresImage;
      environmentFiles = [postgresEnvFile];
      volumes = ["${stateDir}/postgres:/var/lib/postgresql/data"];
      extraOptions = ["--network=${network}"];
    };

    ghostfolio-redis = {
      autoStart = true;
      image = redisImage;
      environmentFiles = [appEnvFile];
      # Redis takes its password on the command line, not from the environment.
      entrypoint = "/bin/sh";
      cmd = ["-c" "exec redis-server --requirepass \"$REDIS_PASSWORD\""];
      extraOptions = ["--network=${network}"];
    };

    ghostfolio = {
      autoStart = true;
      image = ghostfolioImage;
      environmentFiles = [appEnvFile];
      # Bind to the tailnet address only -- never 0.0.0.0.
      ports = ["${tailnetIP}:${toString port}:3333"];
      extraOptions = ["--network=${network}"];
    };
  };
}
