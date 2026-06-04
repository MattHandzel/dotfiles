# modules/core/aes-metrics-collector.nix
#
# MAT-149 — schedule the Agent Execution System (AES) metrics collector.
#
# A single systemd timer+service that runs the metrics collector
#   /home/matth/Projects/agent-execution-system/scripts/metrics/run-collector.sh
# every 30 minutes. The collector snapshots the live Linear board (team MAT,
# project "Agent Execution System") + local tool-error logs and upserts a durable
# SQLite store (~/.local/share/aes-metrics/metrics.db) + an append-only events.jsonl
# replay journal, so we can MEASURE the system improving over time (cycle time,
# review-queue latency, rework, drop rate, throughput) instead of guessing.
#
# IDEMPOTENT by design — the collector replays each issue's full Linear history and
# recomputes that issue's derived rows every run, so re-running is safe; only the
# time-series snapshots + journal grow. run-collector.sh is flock-guarded so an
# overlapping fire can't race. Deterministic Python/bash (stdlib only) — NOT a
# `claude` instance, so it does not touch the single-live-orchestrator rule.
#
# Secrets: the collector reads LINEAR_API_KEY from the vault .env via lib.sh
# (scripts/metrics/lin_fetch.sh sources it) — no sops needed, exactly like the other
# headless Linear jobs (linear-vault-attachments, tw-linear-bridge).
#
# DEPENDENCY: unlike the vault scripts (Syncthing-synced), the AES repo is a plain
# git clone at /home/matth/Projects/agent-execution-system and does NOT sync across
# machines (tracked by MAT-510). The repo must be present at that path on this host
# (matts-server) — it is. The vault symlinks into the repo for lib.sh.
#
# ─────────────────────────────────────────────────────────────────────────────
# WIRED via one import line in modules/core/server.nix:
#     (import ./aes-metrics-collector.nix)
# Nothing runs until Matt rebuilds with scripts/nixos-safe-rebuild.sh.
# The collector ALSO works standalone immediately (no rebuild needed):
#     python3 scripts/metrics/aes_metrics.py collect && \
#       python3 scripts/metrics/aes_metrics.py report
#
# TIMEZONE: server clock is America/Los_Angeles; OnCalendar is server-local. The
# cadence is wall-clock-independent (every 30 min), so TZ doesn't matter here.
# ─────────────────────────────────────────────────────────────────────────────
{ pkgs, ... }:
let
  collector = "/home/matth/Projects/agent-execution-system/scripts/metrics/run-collector.sh";
  # Tools the collector + run-collector.sh + lib.sh need on PATH: python3 (the
  # collector), flock (util-linux, single-flight lock), and the jq/curl/rg/etc.
  # the Linear read shim + lib.sh use.
  toolPath = with pkgs; [ bash coreutils gnugrep gnused gawk findutils jq fd curl ripgrep file util-linux python3 ];
in {
  systemd.services.aes-metrics-collector = {
    description = "MAT-149: snapshot AES metrics from the live Linear board into the durable store";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = toolPath;
    environment = {
      HOME = "/home/matth";
      AES_METRICS_DIR = "/home/matth/.local/share/aes-metrics";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${pkgs.bash}/bin/bash ${collector}";
      TimeoutStartSec = "10min";   # one paginated board pull + local-log parse; fast
      Nice = 10;
    };
  };

  systemd.timers.aes-metrics-collector = {
    description = "Collect AES metrics every 30 min (MAT-149)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/30";        # every 30 minutes (:00 and :30)
      Persistent = true;            # catch up after downtime
      RandomizedDelaySec = "90s";   # don't fire exactly on the minute with other timers
    };
  };
}
