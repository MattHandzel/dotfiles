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
#   * MAT-617 obligation reconciler (the daemon also runs the level-triggered no-drop
#                                  reconcile + boot/wake COLD-START sweep, and writes a
#                                  reconcile heartbeat ~/.claude/self-improve/heartbeats/
#                                  reconciler.json each healthy tick + the obligation ledger
#                                  ~/.claude/conductor/obligations/<host>.ndjson. O1 wires
#                                  reconciler.json into the dead-man's-switch; R1 only writes it.)
#   * MAT-620 O1 dead-man's-switch (a SEPARATE timer — conductor-reliability-alarm — runs every
#                                  5 min INDEPENDENT of the daemon, so it fires even when the
#                                  daemon is dead: it pages Matt on dead_letter>0, oldest-obligation
#                                  past-SLE, OR a STALE reconciler.json heartbeat. The daemon also
#                                  emits the dashboard state.json — incl. the .reconcile block —
#                                  each loop via conductor-state.sh.)
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
    util-linux procps systemd python3 tmux
  ];
in {
  ##### The Conductor daemon — always-on, reboot- + crash-survivable ##########
  systemd.services.linear-watcherd = {
    description = "MAT-507: Conductor — the single shared Linear watcher daemon (poll once, fan out per project)";
    # MAT-573: the daemon SPAWNS orchestrators into `tmux -L fleet`, whose socket dir is $TMUX_TMPDIR.
    # That dir is /run/user/1000, created by user-runtime-dir@1000.service (kept alive at boot by
    # `loginctl enable-linger matth`). Order the daemon AFTER it so the first spawn lands in the same
    # server Matt's `fleet attach` uses — never the /tmp fallback (the headless-orchestrator bug).
    after = [ "network-online.target" "ntfy-sh.service" "user-runtime-dir@1000.service" ];
    wants = [ "network-online.target" "user-runtime-dir@1000.service" ];
    wantedBy = [ "multi-user.target" ];   # start on boot
    path = toolPath;
    environment = {
      HOME = "/home/matth";
      VAULT = "/home/matth/Obsidian/Main";
      POLL_SECONDS = "60";
      # MAT-573: pin the tmux socket DIRECTORY so the daemon's fleet server == Matt's interactive one.
      # tmux locates its socket under $TMUX_TMPDIR (default /tmp; it does NOT read $XDG_RUNTIME_DIR).
      # Matt's home-manager sets TMUX_TMPDIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}, so his attach
      # lands in /run/user/1000/tmux-1000/fleet. Set BOTH here to that same dir so the daemon, its
      # dash window, and every spawn share ONE server — exactly where `fleet attach` looks. Without
      # this the systemd daemon (no such var) defaulted to /tmp → "spawned but no server" (MAT-573).
      # (conductor-spawn.sh / fleet.sh re-pin defensively too, falling back to /tmp only if the
      # runtime dir isn't writable yet — but the After= above ensures it exists before first spawn.)
      XDG_RUNTIME_DIR = "/run/user/1000";
      TMUX_TMPDIR = "/run/user/1000";
      # on-box ntfy — never the external hostname (focus-DNS sinkhole guard, MAT-398)
      NTFY_SERVER = "http://localhost:8124";
      NTFY_TOPIC_PREFIX = "claude-fleet";
      # ── GO-LIVE (MAT-523, 2026-06-05): autospawn ENABLED — the Conductor now spawns
      #    per-project orchestrators on demand. Set back to "0" to disable. Every spawn is
      #    still gated by the MAT-505 governor (budget/cooldown/concurrency), active-hours,
      #    one-per-project /proc liveness, and idle-exit (MAT-503). Watchdog stays OFF for
      #    the first cycle (CONDUCTOR_WATCHDOG default 0) — flip later once this proves out.
      CONDUCTOR_AUTOSPAWN = "1";
      # ── GO-LIVE (MAT-665, 2026-06-12): auto-recovery flipped from observe-only (dry-run) to LIVE.
      #    The deep-robustness build (orphan-recovery + claim-recover) soaked observe-only for days,
      #    mutating nothing; these two flags arm the actuators so a stranded card is automatically
      #    driven back to an owner instead of waiting for a human-spawned session (the MAT-500 red-team's
      #    top reliability gap — 20h-idle ALARM with nothing progressing). Recovery is CONSERVATIVE: it
      #    only resets a no-live-owner OR claimed-but-idle card to Todo and re-drives it; the squash-merge
      #    FALSE-orphan class is proven-closed (MAT-666 merged-PR guard + MAT-675 offline git-log fallback,
      #    each with a discriminating negative control). Rollback is trivial: set both back to "0" + rebuild.
      #      • CONDUCTOR_AUTORECOVER → orphan-recovery (no-live-owner card → reset → re-drive), reconciler tick.
      #      • CONDUCTOR_CLAIMRECOVER → claim-recover (claimed-but-idle → poke → escalate → reset), daemon poll.
      CONDUCTOR_AUTORECOVER = "1";
      CONDUCTOR_CLAIMRECOVER = "1";
      # ── MAT-617 obligation reconciler (the no-drop spine) ──
      # The daemon runs a level-triggered reconcile tick every RECONCILE_EVERY polls + a full-board
      # COLD-START sweep on boot/wake (RECONCILE_COLD_START). Tracking (the durable ledger + metrics +
      # reconcile heartbeat) is always-on; the drive→spawn reuses the SAME governor as autospawn above
      # (so with CONDUCTOR_AUTOSPAWN=0 the ledger still gives full no-drop visibility, just no spawns).
      RECONCILE_EVERY = "2";          # ~120s @ POLL_SECONDS=60; set "0" to disable the standing tick
      RECONCILE_COLD_START = "1";     # run the boot/wake full-board sweep (the MAT-582 fix); "0" to disable
      # ── MAT-906 auto-review merge pipeline (DEFAULT-OFF — ships dark) ──
      # The deterministic verify+merge of In-Review cards with an open PR (auto-review.sh, MAT-891), wired
      # as a daemon side-job. Empty AUTOREVIEW ⇒ the block is a strict NO-OP (no scan, no merge, no extra
      # reads). The go-live is a TWO-STEP soak, exactly like the MAT-665 recovery flags above:
      #   1) set AUTOREVIEW = "dry"  → the daemon LOGS each verdict (WOULD-MERGE / WOULD-RE-ENGAGE) to the
      #      journal for ~1 day, acting on nothing — confirm the verdicts match what the orchestrator would do.
      #   2) on sign-off, set AUTOREVIEW = "act" → a PASS auto-squash-merges + advances the card; a FAIL
      #      re-engages the OWNER (no merge, no needs-matt). Rollback is trivial: set back to "" + rebuild.
      # The MAT-700 blind-reviewer verdict plugs in via ARV_VERDICT_CMD when it lands (no change here).
      AUTOREVIEW = "";                # "" = off (default) | "dry" = log verdicts | "act" = merge / re-engage
      AUTOREVIEW_EVERY = "5";         # scan cadence (polls; ~5 min @ 60s); the per-card verify is heavy. "0" = off.
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
      # ── MAT-921: DECOUPLE the daemon's lifecycle from the fleet it spawns ──────────────────
      # The whole fleet (the `tmux -L fleet` server + every orchestrator/teammate claude) is
      # spawned by this daemon and — because cgroup membership is inherited at fork and survives
      # tmux's reparent-to-init — every one of those processes lives INSIDE this unit's cgroup.
      # With the systemd DEFAULT KillMode=control-group, a daemon restart for ANY reason — a
      # WatchdogSec miss, a manual `systemctl restart`, a deploy — sends the kill signal to the
      # ENTIRE cgroup, decapitating the fleet. That is exactly what happened 2026-06-12 16:58:28Z:
      # an `auto-review.sh act` loop leaked ~18.8K bash subprocesses, fork-starved the daemon so it
      # couldn't fork `systemd-notify WATCHDOG=1` for 5 min, the watchdog fired, and control-group
      # kill SIGABRT'd 20,184 processes — the whole fleet — at once (MAT-921).
      # KillMode=process makes a restart signal ONLY the main daemon PID (a ~5 MB bash). The tmux
      # fleet (already PPID 1, fully detached) survives untouched; the restarted daemon RE-ADOPTS
      # it — the spawn path is idempotent (`tmux has-session` guards `new-session`; there is no
      # `kill-server` anywhere in the daemon/spawn path). So a daemon-level fault can no longer
      # take the fleet down — it just bounces the cheap poller. (systemd still SIGKILLs the cgroup
      # after TimeoutStopSec on a genuine FULL stop — an intentional teardown still cleans up.)
      KillMode = "process";
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

  ##### MAT-620 (O1): the obligation/reconcile DEAD-MAN'S-SWITCH ###################
  # A SEPARATE, frequent timer — deliberately NOT inside the daemon loop. The third alarm trigger
  # is "the reconcile heartbeat went stale" (the daemon/reconcile loop died); if this check only ran
  # inside that loop, a dead daemon would never fire it. Running it as its own timer means a dead or
  # wedged Conductor is caught LOUDLY. The check itself is pure local read (no Linear API): it pages
  # Matt (high-pri ntfy on claude-fleet-alerts) the instant dead_letter_count>0, the oldest open
  # obligation is past its SLE, OR reconciler.json is stale — deduped per-trigger (≤1/h), recover on clear.
  systemd.services.conductor-reliability-alarm = {
    description = "MAT-620 (O1): obligation/reconcile dead-man's-switch — page Matt on dead-letter / past-SLE / stale reconciler";
    after = [ "network.target" "ntfy-sh.service" ];
    path = toolPath;
    environment = {
      HOME = "/home/matth";
      VAULT = "/home/matth/Obsidian/Main";
      NTFY_SERVER = "http://localhost:8124";
      NTFY_TOPIC_PREFIX = "claude-fleet";
    };
    unitConfig.OnFailure = "conductor-reliability-alarm-failure-notify.service";
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${pkgs.bash}/bin/bash ${repo}/scripts/linear/conductor-reliability.sh alarm";
      TimeoutStartSec = "90s";
      Nice = 12;
    };
  };
  systemd.timers.conductor-reliability-alarm = {
    description = "Fire the O1 reliability dead-man's-switch every 5 min (MAT-620)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";          # every 5 minutes
      Persistent = true;
      RandomizedDelaySec = "30s";
    };
  };

  ##### OnFailure: the alarm's OWN dead-man's-switch (page if the alarm can't even run) ##########
  # The dead-man's-switch is only useful if it runs; if the alarm service itself fails (jq/curl
  # missing, script error), that silence would hide a real outage — so make the alarm's failure loud too.
  systemd.services.conductor-reliability-alarm-failure-notify = {
    description = "ntfy Matt if the O1 reliability alarm (conductor-reliability-alarm) fails to run";
    path = with pkgs; [ curl coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = pkgs.writeShellScript "conductor-reliability-alarm-failed" ''
        ${pkgs.curl}/bin/curl -s --max-time 10 \
          -H "Title: O1 reliability alarm FAILED to run" \
          -H "Priority: high" -H "Tags: rotating_light,warning" \
          -d "conductor-reliability-alarm (the obligation/reconcile dead-man's-switch) FAILED on matts-server — the no-drop status check itself isn't running, so a real drop/stall could go unseen. Check:  systemctl status conductor-reliability-alarm ; journalctl -u conductor-reliability-alarm -n 60" \
          http://localhost:8124/claude-fleet-alerts >/dev/null 2>&1 || true
      '';
    };
  };

  ##### MAT-622 (E2): the NO-DROP CHAOS EVAL — weekly regression guard (DEFAULT-OFF) ##########
  # The eval that turns "0.998" into a MEASURED number: it injects synthetic obligations, runs the
  # exact failure modes (kill the fleet mid-run, reboot, force a governor refusal, boot a full
  # backlog) and asserts none drop — scored by E1 (aes_metrics.py reliability). Every future
  # reliability change must keep it green (the regression guard).
  #
  # ┌─ WHY THIS IS SAFE TO RUN ON THE LIVE BOX ──────────────────────────────────────────────┐
  # │ The eval is FULLY HERMETIC. It drives the REAL reconciler but against a FIXTURE board in │
  # │ a private mktemp sandbox with isolated ledger/state/bus dirs; it NEVER reads or writes    │
  # │ the real Linear board or the real obligation ledger, and NEVER runs pkill / touches tmux  │
  # │ — "kill the fleet" is a kill -9 of the eval's OWN test-daemon subprocess. So it cannot     │
  # │ disturb the live linear-watcherd above. (A startup guard refuses to run if any path        │
  # │ escapes the sandbox.)                                                                      │
  # └────────────────────────────────────────────────────────────────────────────────────────┘
  #
  # GATING: per the MAT-622 safety directive the WEEKLY auto-run ships DEFAULT-OFF (timer.enable =
  # false) until Matt signs off. The service is still defined, so it can be run ON-DEMAND any time:
  #     systemctl start linear-watcherd-chaos-eval        # one-shot, logs to the journal
  #     journalctl -u linear-watcherd-chaos-eval -n 60
  # To turn the weekly guard ON later, flip `enable = false` → `true` on the timer below and rebuild.
  #
  # ⚠️ L1/MAT-590 COORDINATION: MAT-590 also edits this module (the orchestrator-longevity / idle-exit
  # wiring, in the daemon's environment block above). THIS is a self-contained block APPENDED at the
  # end — it shares no lines with L1's edits, so the two merge cleanly. Keep it last.
  systemd.services.linear-watcherd-chaos-eval = {
    description = "MAT-622 (E2): no-drop chaos eval — hermetic regression guard for the 0.998 guarantee";
    after = [ "network.target" ];
    path = toolPath;
    environment = {
      HOME = "/home/matth";
      VAULT = "/home/matth/Obsidian/Main";
      # on-box ntfy (unused by the hermetic eval, but present for parity with the other units)
      NTFY_SERVER = "http://localhost:8124";
      NTFY_TOPIC_PREFIX = "claude-fleet";
    };
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${pkgs.bash}/bin/bash ${repo}/scripts/linear/reliability-chaos-eval.sh";
      TimeoutStartSec = "5min";   # the eval runs in ~1 min; generous headroom
      Nice = 15;                  # lowest priority — never competes with the live daemon
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "chaos-eval";
    };
  };
  systemd.timers.linear-watcherd-chaos-eval = {
    description = "MAT-622 (E2): weekly no-drop chaos eval (DEFAULT-OFF until Matt signs off)";
    # enable=false ⇒ declared but NOT started: the weekly auto-run is GATED OFF. Flip to true to arm.
    enable = false;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 04:30";   # weekly, deep in quiet hours (won't contend with real work)
      Persistent = true;
      RandomizedDelaySec = "300s";
    };
  };

  ##### MAT-654: the REQUIREMENT CANARY — continuous self-detecting invariants ##################
  # Requirements-as-canaries: every ~30 min a STANDALONE timer (deliberately NOT inside the
  # linear-watcherd loop — that file is a hotspot MAT-635/636 also touch, and an in-loop probe could
  # never catch a dead daemon) runs requirement-canary.sh, which PROBES each critical invariant by
  # asserting its REAL property (a real spawn produces an attachable window; a real obligation CLOSES;
  # the kill-guard actually BLOCKS a fatal pkill; the wake-path delivers) — never a heartbeat proxy
  # (the MAT-643 trap). It writes ~/.claude/conductor/canary-results.json, which O1's
  # conductor-reliability.sh reads as a 4th alarm trigger (requirement_broken), and ntfys Matt directly
  # on any break — so a silently-broken requirement (like the MAT-573 headless-spawn) is caught + paged
  # WITHOUT Matt having to be the detector.
  #
  # ┌─ WHY THIS IS SAFE TO RUN ON THE LIVE BOX ──────────────────────────────────────────────┐
  # │ The DEFAULT probe set is HERMETIC: the spawn probe drives the real spawn_orchestrator      │
  # │ against a STUB tmux in a private mktemp sandbox; the reconcile probe drives the real        │
  # │ obl_reconcile against an ISOLATED ledger; the kill-guard probe feeds the real hook a test   │
  # │ command (it exits 2/0, runs nothing); the wake probe READS the daemon's poll heartbeat.     │
  # │ NONE create a real Linear issue, spawn a real orchestrator, kill anything, or touch the     │
  # │ real ledger. The LIVE end-to-end canary (inject a real Todo into the dedicated canary       │
  # │ project) is GATED OFF (CANARY_LIVE unset) until Matt registers a canary project + arms it.  │
  # │ Safe auto-remediation is conservative: it only restarts the systemd-managed daemon for a    │
  # │ dead wake-path — never spawns, never broad-kills, never edits the board.                     │
  # └────────────────────────────────────────────────────────────────────────────────────────┘
  #
  # SELF-CONTAINED block appended LAST (shares no lines with the daemon env block or the chaos-eval
  # block above), so it merges cleanly alongside MAT-590/635/636 edits to this file.
  systemd.services.requirement-canary = {
    description = "MAT-654: requirement canary — probe each critical invariant's REAL property, alarm + remediate on a break";
    after = [ "network.target" "ntfy-sh.service" "linear-watcherd.service" ];
    path = toolPath;
    environment = {
      HOME = "/home/matth";
      VAULT = "/home/matth/Obsidian/Main";
      NTFY_SERVER = "http://localhost:8124";
      NTFY_TOPIC_PREFIX = "claude-fleet";
      # the kill-guard hook under test lives in ~/.claude/hooks (deployed by bootstrap.sh).
      KILL_GUARD_SH = "/home/matth/.claude/hooks/kill-guard.sh";
      # HERMETIC probe registry by default. The LIVE end-to-end spawn canary stays OFF (CANARY_LIVE
      # unset) until a dedicated canary project is registered + Matt arms it — see the script header.
      CANARY_PROBES = "spawn,reconcile,killguard,wake";
      CANARY_REMEDIATE = "1";   # safe auto-fix (restart the daemon for a dead wake-path) before alarming
    };
    unitConfig.OnFailure = "requirement-canary-failure-notify.service";
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${pkgs.bash}/bin/bash ${repo}/scripts/linear/requirement-canary.sh run";
      TimeoutStartSec = "4min";   # generous: the live canary (when armed) waits up to CANARY_CLAIM_TIMEOUT
      Nice = 14;
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "requirement-canary";
    };
  };
  systemd.timers.requirement-canary = {
    description = "MAT-654: run the requirement canary every ~30 min";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:7/30";          # every 30 min at :07/:37 (offset from the other timers)
      Persistent = true;
      RandomizedDelaySec = "60s";
    };
  };

  ##### OnFailure: the canary's OWN dead-man's-switch (page if the canary can't even run) ##########
  # A canary is only useful if it RUNS. If requirement-canary.sh itself fails (jq/curl missing, a
  # script error, a sandbox-escape refusal), that silence would hide a real break — so make the
  # canary's own failure loud. (This is the canary-stopped-running case O1 deliberately does NOT
  # alarm on, so it must be covered here.)
  systemd.services.requirement-canary-failure-notify = {
    description = "ntfy Matt if the requirement canary (requirement-canary) fails to run";
    path = with pkgs; [ curl coreutils ];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = pkgs.writeShellScript "requirement-canary-failed" ''
        ${pkgs.curl}/bin/curl -s --max-time 10 \
          -H "Title: Requirement canary FAILED to run" \
          -H "Priority: high" -H "Tags: rotating_light,warning" \
          -d "requirement-canary (MAT-654) FAILED on matts-server — the invariant probes themselves did not run, so a silently-broken requirement could go undetected. Check:  systemctl status requirement-canary ; journalctl -u requirement-canary -n 80" \
          http://localhost:8124/claude-fleet-alerts >/dev/null 2>&1 || true
      '';
    };
  };
}
