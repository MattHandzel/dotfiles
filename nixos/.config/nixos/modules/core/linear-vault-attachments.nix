# modules/core/linear-vault-attachments.nix
#
# MAT-438 — auto-attach vault docs that a Linear issue references.
# (Matt: "whenever there is a linear issue that references a doc in the vault, the doc
#  is automatically uploaded to linear … make it automatic … persistent in case the
#  plumbing changes.")
#
# A single systemd timer+service that runs the RECONCILIATION SWEEP
#   /home/matth/Obsidian/Main/scripts/linear/sync-vault-attachments.sh
# every 30 minutes. The sweep reconciles the CURRENT state of every team-MAT issue —
# it scans description + comments for `file://…/Obsidian/Main/…`, bare-absolute, and
# relative vault paths and ensures each referenced doc is present as a Linear
# attachment. Because it reads issue STATE (not a write event) it is independent of
# HOW the reference got there — MCP, lib.sh, the Linear web/mobile UI, or a future
# tool — so it survives any write-path change. Idempotent + self-healing (title+hash
# dedup; re-attaches if deleted; refreshes when the doc changes on disk).
#
# Deterministic bash (like strip-needsmatt / tw-linear-reconcile) — NOT a `claude`
# instance, so it does not touch the single-live-orchestrator rule. The logic lives in
# the vault script (Syncthing-synced) so behaviour ships without a rebuild; this module
# only schedules it. Secrets: the script reads LINEAR_API_KEY from the vault .env via
# lib.sh (no sops needed), exactly like the other headless Linear jobs.
#
# ─────────────────────────────────────────────────────────────────────────────
# WIRED via one import line in modules/core/server.nix:
#     (import ./linear-vault-attachments.nix)
# Nothing runs until Matt rebuilds with scripts/nixos-safe-rebuild.sh.
# The sweep ALSO works standalone immediately (no rebuild needed):
#     scripts/linear/sync-vault-attachments.sh --dry     # preview scope
#     scripts/linear/sync-vault-attachments.sh           # reconcile for real
#
# TIMEZONE: server clock is America/Los_Angeles; OnCalendar is server-local. The
# cadence is wall-clock-independent (every 30 min), so TZ doesn't matter here.
# ─────────────────────────────────────────────────────────────────────────────
{ pkgs, ... }:
let
  sweep = "/home/matth/Obsidian/Main/scripts/linear/sync-vault-attachments.sh";
  # Deterministic tools the sweep + lib.sh need on PATH (rg for PCRE2 detection,
  # file for MIME fallback, the rest for jq/curl/sha256sum/realpath/date/…).
  toolPath = with pkgs; [ bash coreutils gnugrep gnused gawk findutils jq fd curl ripgrep file ];
in {
  systemd.services.linear-vault-attachments = {
    description = "MAT-438: auto-attach vault docs referenced in Linear issues (reconciliation sweep)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = toolPath;
    environment = { HOME = "/home/matth"; };
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${pkgs.bash}/bin/bash ${sweep}";
      TimeoutStartSec = "20min";   # a full team scan + any uploads; bounded by --limit
      Nice = 10;
    };
  };

  systemd.timers.linear-vault-attachments = {
    description = "Reconcile Linear ↔ vault-doc attachments every 30 min (MAT-438)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/30";        # every 30 minutes (:00 and :30)
      Persistent = true;            # catch up after downtime
      RandomizedDelaySec = "90s";   # avoid firing exactly on the minute with other timers
    };
  };
}
