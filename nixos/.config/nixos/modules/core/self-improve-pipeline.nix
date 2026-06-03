# modules/core/self-improve-pipeline.nix
#
# MAT-61 — make the agent self-improvement pipeline a proper NixOS thing.
# (Matt: "lets make this be a nixos thing." See areas/second-brain/agent-self-improvement-system.md.)
#
# Two systemd timer+service pairs on the server. Both run HEADLESS `claude -p` —
# the Matt-approved single-orchestrator carve-out (a deliberately NON-orchestrating
# analytical instance; MAT-61 point 2). The logic lives in the vault scripts
# (scripts/self-improve/*, Syncthing-synced) so fixes ship without a rebuild.
#
#   1. self-improve-analysis  (MAT-182) — WEEKLY mistake-mining:
#        run-retro-sweep --headless → file-agent-errors file → measure.
#        (run-analysis-pass.sh — ntfy-alerts on failure; MAT-120 watchdog also
#         catches the stale `filer` heartbeat.)
#
#   2. self-improve-enrich    (MAT-183) — DAILY enricher:
#        consolidate-prompts → enrich-prompts headless (enriched CONVERSATION_HISTORY
#        + SPEC.md changelog, redacted + noise-filtered).
#        (run-enrich-pass.sh — emits an `enricher` heartbeat for MAT-120; ntfy on fail.)
#        WRITES VAULT FILES: areas/second-brain/CONVERSATION_HISTORY.md and SPEC.md.
#        consolidate is single-writer → the orchestrator stops running it by hand.
#
# `claude` (user npm-global binary) + `node` (per-user nix profile) are put on
# PATH by the wrapper scripts themselves; this module's `path` supplies the
# deterministic tools (jq/fd/curl/coreutils/…). claude authenticates via
# ~/.claude/.credentials.json (HOME is set); verified working headless on the server.
#
# ─────────────────────────────────────────────────────────────────────────────
# PROPOSE-DON'T-APPLY (NixOS safety rule + MAT-61): WRITTEN, NOT WIRED.
# To activate, add ONE line to the imports in modules/core/server.nix:
#     (import ./self-improve-pipeline.nix)
# then rebuild via scripts/nixos-safe-rebuild.sh (Matt runs it). Nothing here runs
# until both are done.
#
# TIMEZONE: the server's TZ is America/Los_Angeles (Pacific) — verified via
# `timedatectl`. OnCalendar uses server-local time, so these fire at Pacific time:
#   analysis: Sun 03:00 PT — early Sunday, before the MAT-120 weekly digest.
#   enrich:   daily 04:00 PT — overnight.
# (NB: the older "server is Central" note in CLAUDE.md/memory is stale for the host
#  clock; it may still be true for ntfy message timestamps specifically.)
# ─────────────────────────────────────────────────────────────────────────────
{ pkgs, ... }:
let
  selfImprove = "/home/matth/Obsidian/Main/scripts/self-improve";
  toolPath = with pkgs; [ bash coreutils gnugrep gnused gawk findutils jq fd curl ];
  commonService = {
    Type = "oneshot";
    User = "matth";
  };
  commonEnv = { HOME = "/home/matth"; };
in {
  ##### 1. WEEKLY mistake-mining (sweep → file → measure), headless ###########
  systemd.services.self-improve-analysis = {
    description = "MAT-61/MAT-182: weekly headless self-improvement sweep → file agent-errors → measure";
    after = [ "network-online.target" "ntfy-sh.service" ];
    wants = [ "network-online.target" ];
    path = toolPath;
    environment = commonEnv;
    serviceConfig = commonService // {
      ExecStart = "${pkgs.bash}/bin/bash ${selfImprove}/run-analysis-pass.sh";
      TimeoutStartSec = "1h";    # a real sweep mines many transcripts via claude -p
    };
  };
  systemd.timers.self-improve-analysis = {
    description = "Weekly self-improvement mistake-mining pass (Sun 03:00 PT)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 03:00:00";
      Persistent = true;         # catch up after downtime
    };
  };

  ##### 2. DAILY enricher (consolidate → enrich headless), writes vault docs ##
  systemd.services.self-improve-enrich = {
    description = "MAT-61/MAT-183: daily headless enricher → CONVERSATION_HISTORY + SPEC.md";
    after = [ "network-online.target" "ntfy-sh.service" ];
    wants = [ "network-online.target" ];
    path = toolPath;
    environment = commonEnv;
    serviceConfig = commonService // {
      ExecStart = "${pkgs.bash}/bin/bash ${selfImprove}/run-enrich-pass.sh";
      TimeoutStartSec = "30min";
    };
  };
  systemd.timers.self-improve-enrich = {
    description = "Daily self-improvement enricher pass (04:00 PT)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
    };
  };
}
