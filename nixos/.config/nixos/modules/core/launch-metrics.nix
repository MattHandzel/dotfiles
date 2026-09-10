# launch-metrics.nix — daily GitHub metrics snapshot for the open-source launch system.
#
# GitHub deletes traffic data (views/clones) after 14 days, so a missed fortnight is data
# lost forever. This runs scripts/launch/metrics-snapshot.sh once a day and appends a line
# to each repo's metrics.jsonl. Two consecutive lines = the loop is wired.
#
# SECRET — Matt must do this before importing this module:
#   1. `sops secrets/secrets.yaml` and add `github-launch-metrics-token: ghp_...`
#      (a fine-grained PAT with Contents:read + Metadata:read on the launch repos;
#       traffic endpoints need push access on the repo, so use an owner token).
#   2. Then rebuild. Declaring the secret without a value makes ACTIVATION fail, so do
#      not import this module until the value exists in secrets.yaml.
{
  pkgs,
  config,
  ...
}: let
  vault = "/home/matth/Obsidian/Main";
  tokenPath = config.sops.secrets."github-launch-metrics-token".path;

  # metrics-snapshot.sh shells out to gh, jq, curl, bc and coreutils. The server's
  # systemd PATH has none of them, so build the PATH explicitly.
  runSnapshot = pkgs.writeShellScript "launch-metrics-run" ''
    export PATH="${pkgs.gh}/bin:${pkgs.jq}/bin:${pkgs.curl}/bin:${pkgs.bc}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:$PATH"
    export HOME=/home/matth
    export VAULT_ROOT="${vault}"
    # gh reads GH_TOKEN from the env; the sops file is 0400 root:matth-owned.
    GH_TOKEN="$(cat ${tokenPath})"
    export GH_TOKEN
    exec ${pkgs.bash}/bin/bash ${vault}/scripts/launch/metrics-snapshot.sh \
      --all \
      MattHandzel/taskwarrior.nvim \
      MattHandzel/gdoc-sync \
      MattHandzel/gdoc-sync.nvim
  '';
in {
  sops.secrets."github-launch-metrics-token" = {
    owner = "matth";
  };

  systemd.services.launch-metrics = {
    description = "Daily GitHub metrics snapshot for open-source launch runs";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${runSnapshot}";
      # Exit 1 = every repo failed (usually a token problem). Don't spam a failed unit;
      # the missing metrics.jsonl line is the real signal.
      SuccessExitStatus = "0 1";
    };
  };

  systemd.timers.launch-metrics = {
    description = "Run the launch metrics snapshot daily at 09:30 CT";
    wantedBy = ["timers.target"];
    timerConfig = {
      # Explicit zone: the host timezone is America/Los_Angeles (modules/core/system.nix),
      # so a bare "09:30:00" would be 09:30 PT. systemd >= 252 accepts a trailing zone.
      OnCalendar = "*-*-* 09:30:00 America/Chicago";
      Persistent = true;
      Unit = "launch-metrics.service";
    };
  };
}
