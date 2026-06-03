# modules/core/self-improve-watchdog.nix
#
# MAT-120 — the DEAD-MAN'S-SWITCH for the agent self-improvement pipeline.
# (See areas/second-brain/agent-self-improvement-system.md in the vault.)
#
# This module defines three systemd timer+service pairs on the server:
#
#   1. self-improve-watchdog  — runs scripts/self-improve/watchdog.sh `check`
#      HOURLY. Each pipeline stage (capture hook, analyzer, filer, watcher)
#      writes a heartbeat file; the watchdog ntfy-alerts if any stage's heartbeat
#      goes stale past its expected window. (NEGATIVE alarm — fires on failure.)
#
#   2. self-improve-digest    — runs scripts/self-improve/digest.sh `send` WEEKLY
#      (Sunday). A healthy pipeline sends a short "alive + this-week's counts"
#      ntfy; the ABSENCE of that digest is itself the alarm. This also covers the
#      watchdog's own blind spot (if the watchdog/server dies, the digest stops
#      arriving). (POSITIVE alarm — you notice silence.)
#
#   3. self-improve-adoption-gate — runs scripts/self-improve/adoption-gate.sh
#      `check` every 3h. Reopens agent-improvement issues closed to Done without
#      a closeout block (named enforcement + recurrence metric). (MAT-180.)
#
# The logic lives in the vault (scripts/self-improve/*, Syncthing-synced,
# version-controlled); this module is a thin systemd wrapper that execs it, so
# fixes ship by editing the scripts — no rebuild needed for logic changes.
#
# ─────────────────────────────────────────────────────────────────────────────
# PROPOSE-DON'T-APPLY (per NixOS safety rule + MAT-120):
# This file is WRITTEN but NOT YET WIRED. To activate, Matt (or the orchestrator
# with Matt's OK) must:
#   (1) add this one line to the imports list in modules/core/server.nix:
#           (import ./self-improve-watchdog.nix)
#   (2) rebuild with scripts/nixos-safe-rebuild.sh (staged: dry-build → build →
#       test → switch, with interactive confirmation at test + switch).
# Until both are done, nothing here runs. Nothing is auto-applied.
#
# TIMEZONE: the server runs Central time; Matt is Pacific (2h behind). systemd
# OnCalendar uses server-local (CT). The weekly digest fires Sun 11:00 CT =
# Sun 09:00 PT (Sunday morning for Matt).
# ─────────────────────────────────────────────────────────────────────────────
{ pkgs, ... }:
let
  vault = "/home/matth/Obsidian/Main";
  selfImprove = "${vault}/scripts/self-improve";
  # tools the bash scripts need, provided explicitly (systemd PATH is minimal).
  toolPath = with pkgs; [
    bash coreutils gnugrep gnused gawk findutils jq fd curl
  ];
  commonService = {
    Type = "oneshot";
    User = "matth";
  };
  commonEnv = { HOME = "/home/matth"; };
in {
  ##### 1. NEGATIVE alarm: stale-stage watchdog (hourly) #####################
  systemd.services.self-improve-watchdog = {
    description = "MAT-120 dead-man's-switch: alert if a self-improvement pipeline stage stalls";
    after = [ "network.target" "ntfy-sh.service" ];
    path = toolPath;
    environment = commonEnv;
    serviceConfig = commonService // {
      ExecStart = "${pkgs.bash}/bin/bash ${selfImprove}/watchdog.sh check";
    };
  };
  systemd.timers.self-improve-watchdog = {
    description = "Run the self-improvement watchdog hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* *:17:00";   # every hour at :17 (offset from other timers)
      Persistent = true;              # catch up after downtime
    };
  };

  ##### 2. POSITIVE alarm: weekly alive+counts digest #######################
  systemd.services.self-improve-digest = {
    description = "MAT-120 weekly POSITIVE digest: pipeline-alive + this-week's counts (absence = alarm)";
    after = [ "network.target" "ntfy-sh.service" ];
    path = toolPath;
    environment = commonEnv;
    serviceConfig = commonService // {
      ExecStart = "${pkgs.bash}/bin/bash ${selfImprove}/digest.sh send";
    };
  };
  systemd.timers.self-improve-digest = {
    description = "Send the weekly self-improvement digest (Sun 11:00 CT = 09:00 PT)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 11:00:00";
      Persistent = true;
    };
  };

  ##### 3. adoption Done-gate (every 3h) ####################################
  # MAT-180 — reopen agent-improvement issues closed to Done WITHOUT a closeout
  # block (a named enforcement mechanism + a recurrence metric). Non-retroactive:
  # the first run grandfathers the current set; only later closes-without-block
  # bounce. Logic lives in the vault script (no rebuild needed for logic changes).
  systemd.services.self-improve-adoption-gate = {
    description = "MAT-180 adoption gate: reopen agent-improvements closed without a closeout block";
    after = [ "network.target" ];
    path = toolPath;
    environment = commonEnv;
    serviceConfig = commonService // {
      ExecStart = "${pkgs.bash}/bin/bash ${selfImprove}/adoption-gate.sh check";
    };
  };
  systemd.timers.self-improve-adoption-gate = {
    description = "Run the adoption gate every 3h (cheap; catches fresh closes)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00/3:37:00";   # every 3h at :37 (offset from the :17 watchdog)
      Persistent = true;
    };
  };
}
