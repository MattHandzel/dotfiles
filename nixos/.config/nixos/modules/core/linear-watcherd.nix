# nix/linear-watcherd.nix
#
# MAT-507 (+ MAT-458 permanence) — package the Conductor (`linear-watcherd`, the
# SINGLE shared Linear watcher daemon) as a DECLARATIVE NixOS systemd service so
# it survives reboots and crashes. This is the unit the MAT-409 relocation was
# meant to produce; carded separately so it isn't lost.
#
# WHAT THIS GIVES THE CONDUCTOR
#   * starts on boot              (wantedBy = multi-user.target)
#   * auto-restarts on crash      (Restart=always, RestartSec=10)
#   * force-restart when WEDGED   (Type=notify + WatchdogSec; the daemon pings
#                                  `systemd-notify WATCHDOG=1` each loop — a hung
#                                  but-alive daemon is killed+restarted, not left
#                                  silently blind — the MAT-126 lesson)
#   * pages Matt on a crash-LOOP  (startLimitBurst → OnFailure → ntfy, so a hard
#                                  failure is loud, never a silent thrash)
#   * MAT-120 heartbeat           (the daemon writes ~/.claude/self-improve/
#                                  heartbeats/watcherd.json each HEALTHY cycle;
#                                  `fleet dash` + the self-improve watchdog read
#                                  it, so a dead daemon goes visibly STALE)
#
# NOT a `claude` instance — the Conductor only POLLS Linear once team-wide and
# fans deltas out to per-project channels (it never edits issues), so it does not
# touch the single-live-orchestrator rule. (Autonomous SPAWNING is a later,
# feature-flagged, default-OFF step — MAT-502 — gated by the MAT-505 governor.)
#
# DEPENDENCY: the AES repo is a plain git clone at
# /home/matth/Projects/agent-execution-system (does NOT Syncthing-sync; MAT-510).
# The repo must be present at that path on this host (matts-server) — it is. The
# daemon sources lib.sh / registry.sh / heartbeat.sh from the vault
# (/home/matth/Obsidian/Main), which symlinks into the repo — same pattern as
# aes-metrics-collector.nix.
#
# NTFY goes to http://localhost:8124 (the on-box ntfy), NOT the external hostname,
# so focus-DNS (MAT-398) cannot sinkhole the Conductor's own alert path.
#
# ─────────────────────────────────────────────────────────────────────────────
# PROPOSE-DON'T-APPLY (per the NixOS-safety rule + MAT-507):
# This module is AUTHORED but NOT WIRED. The real config is the flake at
# ~/dotfiles/nixos/.config/nixos. A flake can only import files inside its own
# source tree, so copy this module in, then add one import line, then rebuild:
#
#   1) cp /home/matth/Projects/agent-execution-system/nix/linear-watcherd.nix \
#         ~/dotfiles/nixos/.config/nixos/modules/core/linear-watcherd.nix
#      # (re-copy after any future edit to the repo copy — the repo is canonical)
#
#   2) add to the imports list in modules/core/server.nix (next to the other
#      AES units), exactly:
#         (import ./linear-watcherd.nix) # MAT-507 Conductor daemon (reboot-survivable)
#
#   3) rebuild via the safe staged path (interactive confirm at test + switch):
#         ~/Obsidian/Main/scripts/nixos-safe-rebuild.sh remote matts-server dry-build
#         ~/Obsidian/Main/scripts/nixos-safe-rebuild.sh remote matts-server build
#         ~/Obsidian/Main/scripts/nixos-safe-rebuild.sh remote matts-server switch
#      (or, on-box:  cd ~/dotfiles/nixos/.config/nixos && \
#                    sudo nixos-rebuild switch --flake .#server)
#
# Until all three are done, nothing here runs and nothing is auto-applied.
# The daemon ALSO runs standalone immediately (no rebuild needed) for validation:
#     /home/matth/Projects/agent-execution-system/scripts/linear/linear-watcherd --once
# ─────────────────────────────────────────────────────────────────────────────
{ pkgs, ... }:
let
  repo = "/home/matth/Projects/agent-execution-system";
  daemon = "${repo}/scripts/linear/linear-watcherd";
  # The bash daemon + its side-jobs + lib.sh need these on PATH (systemd PATH is
  # minimal). `systemd` provides `systemd-notify` for the Type=notify watchdog.
  # `python3` is for the MAT-505 cost governor's rolling-usage budget check
  # (rolling_usage.py), which the Conductor consults before autospawn (MAT-502).
  toolPath = with pkgs; [
    bash coreutils gnugrep gnused gawk findutils jq fd curl ripgrep file
    util-linux procps systemd python3
  ];
in {
  ##### The Conductor daemon — always-on, reboot- + crash-survivable ##########
  systemd.services.linear-watcherd = {
    description = "MAT-507: Conductor — the single shared Linear watcher daemon (poll once, fan out per project)";
    after = [ "network-online.target" "ntfy-sh.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];   # start on boot
    path = toolPath;
    environment = {
      HOME = "/home/matth";
      VAULT = "/home/matth/Obsidian/Main";
      POLL_SECONDS = "60";
      # on-box ntfy — never the external hostname (focus-DNS sinkhole guard, MAT-398)
      NTFY_SERVER = "http://localhost:8124";
      NTFY_TOPIC_PREFIX = "claude-fleet";
    };

    # A hard crash-LOOP (5 restarts in 10 min) → enter `failed` → fire OnFailure
    # (the ntfy below) instead of thrashing forever in silence.
    startLimitIntervalSec = 600;
    startLimitBurst = 5;
    unitConfig.OnFailure = "linear-watcherd-failure-notify.service";

    serviceConfig = {
      Type = "notify";          # daemon sends READY=1 once initialized
      NotifyAccess = "all";     # accept WATCHDOG=1 from the forked systemd-notify child
      WatchdogSec = "300";      # > poll(60s) + worst-case side-job retries; miss → restart
      User = "matth";
      ExecStart = "${pkgs.bash}/bin/bash ${daemon}";
      Restart = "always";
      RestartSec = 10;
      TimeoutStartSec = "60s";  # plenty for sourcing lib.sh/registry.sh then READY=1
      Nice = 10;
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "linear-watcherd";
    };
  };

  ##### OnFailure: page Matt when the Conductor crash-loops into `failed` ######
  # No silent blindness (MAT-126): if the daemon can't even stay up, the shared
  # poller is DOWN and every subscribing session goes blind — that must be loud.
  systemd.services.linear-watcherd-failure-notify = {
    description = "ntfy Matt when linear-watcherd (the Conductor) enters a failed state";
    path = with pkgs; [ curl coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = pkgs.writeShellScript "linear-watcherd-failed" ''
        ${pkgs.curl}/bin/curl -s --max-time 10 \
          -H "Title: Conductor DOWN (linear-watcherd)" \
          -H "Priority: high" -H "Tags: rotating_light,warning" \
          -d "linear-watcherd (the Conductor) entered a FAILED state on matts-server — it crash-looped past the restart limit. The single shared Linear poller is DOWN; every subscribing session goes blind until it recovers. Check:  systemctl status linear-watcherd ; journalctl -u linear-watcherd -n 80" \
          http://localhost:8124/claude-fleet-alerts >/dev/null 2>&1 || true
      '';
    };
  };

  ##### MAT-508: periodic ntfy activity digest (observability when Matt's away) ####
  # Summarizes the append-only activity log (spawns/teardowns/routes/refusals) + the
  # awaiting-Matt count and ntfys a one-line digest every ~3h. Cadence is the
  # CONDUCTOR_DIGEST_EVERY_H knob; this OnCalendar mirrors it (change both to retune).
  systemd.services.conductor-digest = {
    description = "MAT-508: ntfy digest of autonomous Conductor activity + awaiting-Matt count";
    after = [ "network.target" "ntfy-sh.service" ];
    path = toolPath;
    environment = {
      HOME = "/home/matth";
      VAULT = "/home/matth/Obsidian/Main";
      NTFY_SERVER = "http://localhost:8124";
      NTFY_TOPIC_PREFIX = "claude-fleet";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${pkgs.bash}/bin/bash ${repo}/scripts/linear/conductor-digest.sh send";
      TimeoutStartSec = "2min";
      Nice = 12;
    };
  };
  systemd.timers.conductor-digest = {
    description = "Fire the Conductor activity digest every ~3h (MAT-508)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00/3:23:00";   # every 3h at :23 (offset from other timers)
      Persistent = true;
      RandomizedDelaySec = "120s";
    };
  };
}
