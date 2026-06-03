# /home/matth/dotfiles/nixos/.config/nixos/modules/core/tw-linear-bridge.nix
#
# Taskwarrior -> Linear bridge (Linear MAT-89). PROPOSE-ONLY: this file is
# written by the tw-linear teammate but NOT yet imported or rebuilt. To turn it
# on, Matt adds ONE line to hosts/server/default.nix imports (see the bottom of
# this file) and runs scripts/nixos-safe-rebuild.sh.
#
# Design + decisions: /home/matth/Obsidian/Main/areas/second-brain/taskwarrior-linear-integration.md
# Code (synced to the server via Syncthing): /home/matth/Obsidian/Main/scripts/taskwarrior-linear/
#
# ---------------------------------------------------------------------------
# IMPORTANT architecture note (discovered 2026-06-02):
# The server runs taskchampion-sync-server but has NO Taskwarrior CLIENT, and
# the existing taskwarrior-daily-notify reads a Syncthing-synced JSON export
# (taskwarrior/pending-tasks.json) produced by the laptop. So there are two
# ways to run the bridge; pick with `mode` below:
#
#   mode = "export"  (DEFAULT, zero new provisioning)
#       The reconcile reads the synced export file. Works the moment you rebuild.
#       Limits: push latency = export-cron + reconcile interval (not instant),
#       NO instant hooks, and completions/deletions only propagate if the laptop
#       export includes them (today it exports `status:pending` only — widen it
#       with the one-liner noted at the bottom to sync done/deleted too).
#
#   mode = "replica"  (RECOMMENDED end-state — instant push + writeback)
#       Provisions a real Taskwarrior replica on the server that syncs to the
#       local taskchampion-sync-server, installs the on-add/on-modify/on-exit
#       hooks (instant push), and writes the `linearid` UDA back onto tasks.
#       Requires a secret file (sync client_id + encryption secret) — see below.
# ---------------------------------------------------------------------------

{ pkgs, ... }:

let
  user = "matth";
  mode = "replica";                # "export" | "replica"  — Matt chose REPLICA (2026-06-02)
  # `lin pull_marked` landed in lib.sh (MAT-164) and the Linear->TW pull leg was
  # verified live (2026-06-02), so the pull pass runs alongside the push reconcile.
  pullEnabled = true;

  vault = "/home/${user}/Obsidian/Main";
  bridgeDir = "${vault}/scripts/taskwarrior-linear";
  configFile = "${bridgeDir}/config.json";          # Matt copies config.example.json -> config.json
  exportFile = "${vault}/taskwarrior/pending-tasks.json";
  stateDir = "/home/${user}/.local/state/tw-linear-bridge";
  queueDir = "${stateDir}/queue";

  # Tools the bridge + `lin` (curl/jq) need on PATH.
  runtimePath = pkgs.lib.makeBinPath ([
    pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.curl pkgs.jq pkgs.python3
  ] ++ pkgs.lib.optional (mode == "replica") pkgs.taskwarrior3);

  # Where reconcile gets its tasks.
  reconcileArgs =
    if mode == "export"
    then "--input ${exportFile} --config ${configFile} --db ${stateDir}/mapping.db"
    else "--config ${configFile} --db ${stateDir}/mapping.db";

  commonHardening = {
    User = user;
    WorkingDirectory = bridgeDir;
    Environment = [
      "PATH=${runtimePath}"
      "VAULT=${vault}"
      "LINEAR_AGENT_NAME=tw-linear"
      "TW_LINEAR_QUEUE=${queueDir}"
      "PYTHONUNBUFFERED=1"
    ] ++ pkgs.lib.optionals (mode == "replica") [
      "TASKRC=${stateDir}/taskrc"
      "TASKDATA=/home/${user}/.task"
    ];
    # ProtectHome=read-only lets us READ the vault (.env, scripts) but the state
    # dir must be writable for mapping.db + queue.
    ProtectSystem = "strict";
    ProtectHome = "read-only";
    ReadWritePaths = [ stateDir ]
      ++ pkgs.lib.optional (mode == "replica") "/home/${user}/.task";
    PrivateTmp = true;
    NoNewPrivileges = true;
    LockPersonality = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    SystemCallArchitectures = "native";
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    MemoryMax = "300M";
    CPUQuota = "60%";
    StandardOutput = "journal";
    StandardError = "journal";
  };
in
{
  # state + queue dirs (and replica hooks dir when in replica mode)
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 ${user} users - -"
    "d ${queueDir} 0700 ${user} users - -"
  ];

  # --- Path C: the 10-minute reconcile (correctness guarantee) -------------
  systemd.services."tw-linear-reconcile" = {
    description = "Taskwarrior -> Linear reconcile (MAT-89, ${mode} mode)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = commonHardening // {
      Type = "oneshot";
      TimeoutStartSec = "300s";
      # Push (TW->Linear) every run; pull (Linear->TW) appended once the
      # `lin pull_marked` helper exists. Multiple ExecStart run in order.
      ExecStart = [
        "${pkgs.python3}/bin/python3 ${bridgeDir}/reconcile.py ${reconcileArgs}"
      ] ++ pkgs.lib.optional pullEnabled
        "${pkgs.python3}/bin/python3 ${bridgeDir}/pull.py --config ${configFile} --db ${stateDir}/mapping.db";
    };
  };

  systemd.timers."tw-linear-reconcile" = {
    description = "Run the Taskwarrior -> Linear reconcile every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "10m";
      AccuracySec = "30s";
      Persistent = true;
      Unit = "tw-linear-reconcile.service";
    };
  };

  # --- Path A: instant-push queue drainer (replica mode only) --------------
  # In export mode there are no hooks, so nothing enqueues — the drainer is a
  # no-op and is omitted. In replica mode the hooks enqueue uuids and this
  # drains them every 60s for near-instant push.
  systemd.services."tw-linear-drain" = pkgs.lib.mkIf (mode == "replica") {
    description = "Drain Taskwarrior hook queue -> targeted Linear push";
    after = [ "network-online.target" ];
    serviceConfig = commonHardening // {
      Type = "oneshot";
      TimeoutStartSec = "180s";
      ExecStart = "${pkgs.python3}/bin/python3 ${bridgeDir}/bridge.py --drain --config ${configFile} --db ${stateDir}/mapping.db";
    };
  };

  systemd.timers."tw-linear-drain" = pkgs.lib.mkIf (mode == "replica") {
    description = "Drain the tw-linear push queue every 60s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "90s";
      OnUnitActiveSec = "60s";
      AccuracySec = "10s";
      Persistent = true;
      Unit = "tw-linear-drain.service";
    };
  };

  # --- replica-mode provisioning (Taskwarrior client + sync + hooks) -------
  # Only relevant when mode = "replica". The replica's taskrc `include`s a SECRET
  # file at ${stateDir}/sync.taskrc containing:
  #       sync.server.url=...        (or sync.local.* for local replica)
  #       sync.server.client_id=<the shared task-history client_id>
  #       sync.encryption_secret=<the shared encryption secret>
  # The shared client_id is already allow-listed in taskchampion-sync-server.nix
  # (client_id is per-task-history, shared across devices — no allowlist change).
  #
  # SECRET DELIVERY — two ways; sops is preferred (Matt-action either way):
  #   (preferred) sops:  declare a sops secret NAMED
  #       sops.secrets."tw-linear/taskchampion-sync" = {
  #         owner = "${user}"; path = "${stateDir}/sync.taskrc"; mode = "0400";
  #       };
  #     then `sops -e` the 3 lines above into the server's secrets.yaml under
  #     the key `tw-linear/taskchampion-sync`. NB: matts-server has NO sops-nix
  #     wired into the flake yet (see notify-poller.nix) — wiring it is a
  #     prerequisite; until then use the fallback.
  #   (fallback, works today) hand-create ${stateDir}/sync.taskrc, chmod 0600,
  #     NOT in git. Same content. (Source values: taskwarrior/sync-secrets.md.)
  environment.systemPackages = pkgs.lib.optional (mode == "replica") pkgs.taskwarrior3;

  # The managed taskrc (UDAs + hooks + include of the secret sync file).
  # Written to the state dir so TASKRC can point at it. (Replica mode only.)
  systemd.services."tw-linear-replica-init" = pkgs.lib.mkIf (mode == "replica") {
    description = "Provision the server Taskwarrior replica taskrc for the bridge";
    wantedBy = [ "multi-user.target" ];
    before = [ "tw-linear-reconcile.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      RemainAfterExit = true;
    };
    script = ''
      umask 077
      mkdir -p ${stateDir}
      cat > ${stateDir}/taskrc <<'RC'
      data.location=/home/${user}/.task
      hooks.location=${bridgeDir}/hooks
      # identity UDAs (ride the TaskChampion CRDT to every device, MAT-89 §3.1)
      uda.linearid.type=string
      uda.linearid.label=Linear ID
      uda.linearuuid.type=string
      uda.linearuuid.label=Linear UUID
      uda.linear_synced_at.type=string
      uda.linear_synced_at.label=Linear synced at
      # sync credentials — create this file by hand, 0600, NOT in git:
      include ${stateDir}/sync.taskrc
      RC
    '';
  };

  systemd.services."tw-linear-sync" = pkgs.lib.mkIf (mode == "replica") {
    description = "task sync (pull other devices' edits into the server replica)";
    after = [ "network-online.target" "tw-linear-replica-init.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Environment = [ "PATH=${runtimePath}" "TASKRC=${stateDir}/taskrc" "TASKDATA=/home/${user}/.task" ];
      ExecStart = "${pkgs.taskwarrior3}/bin/task sync";
      TimeoutStartSec = "60s";
    };
  };

  systemd.timers."tw-linear-sync" = pkgs.lib.mkIf (mode == "replica") {
    description = "task sync every 2 minutes (feed the reconcile + hooks)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnUnitActiveSec = "2m";
      Persistent = true;
      Unit = "tw-linear-sync.service";
    };
  };
}

# ===========================================================================
# REPLICA MODE — Matt has exactly TWO actions (the agent did NOT do these):
#
#   ACTION 1 — the sync secret (sops secret name: `tw-linear/taskchampion-sync`).
#   Provide the TaskChampion sync credentials so they land at
#     /home/matth/.local/state/tw-linear-bridge/sync.taskrc
#   with the 3 lines from any existing replica (laptop ~/.taskrc):
#       sync.server.url=...                 (or sync.local.server=... for local)
#       sync.server.client_id=<shared task-history client_id>
#       sync.encryption_secret=<shared encryption secret>
#   PREFERRED: sops — `sops -e` these under key `tw-linear/taskchampion-sync` and
#   declare `sops.secrets."tw-linear/taskchampion-sync".path = "<the path above>"`.
#   NOTE: matts-server has NO sops-nix wired into the flake yet (see
#   notify-poller.nix); wiring it is a prerequisite. FALLBACK (works today):
#   hand-create that file, chmod 0600, NOT in git (values in taskwarrior/sync-secrets.md).
#   The shared client_id is ALREADY allow-listed in taskchampion-sync-server.nix
#   (client_id is per-task-history, shared across devices — no allowlist change).
#
#   ACTION 2 — enable + rebuild.  Add ONE import line to hosts/server/default.nix
#   (the imports = [ ... ] list):
#        ./../../modules/core/tw-linear-bridge.nix
#   then run the staged safe-rebuild (you confirm at test/switch):
#        bash ~/dotfiles/nixos/.config/nixos/  → scripts/nixos-safe-rebuild.sh
#
# That's it. config.json is optional — the bridge auto-uses config.example.json
# (the proposed project map) until you create config.json to refine it; and no
# bulk sync happens until you confirm the mapping on MAT-89. The Linear->TW pull
# pass turns on by flipping `pullEnabled = true` once `lin pull_marked` lands.
# ===========================================================================
