{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  # Platform test from the `host` specialArg, not from `pkgs` — see the
  # comment at the top of lib/scheduled.nix for why.
  isDarwin = host == "mac";
  isLinux = !isDarwin;
  notesDir = "${config.home.homeDirectory}/notes";
  vaultDir = "${config.home.homeDirectory}/Obsidian/Main";

  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
  inherit (import ./lib/platform-scripts.nix {inherit pkgs;}) notify;

  # The sync's Python env, built once at switch time from this flake's locked
  # nixpkgs. The job used to run `nix-shell ~/Projects/website/shell.nix`, whose
  # <nixpkgs> floats (Determinate's nix-path, nixpkgs-weekly): every week the
  # hourly run re-fetched nixpkgs and rebuilt its env, so a DNS blip mid-fetch
  # (2026-11-06, cache.nixos.org) or a flaky timing test in a package built
  # locally (2026-11-09, feedparser-sgmllib) exited 1
  # (err-personal-website-sync-20261103-132051). Same package list as shell.nix's
  # Python part; keep them in step. shell.nix stays for interactive dev.
  websiteSyncPython = pkgs.python312.withPackages (ps:
    with ps; [
      pyyaml
      pymongo
      python-dotenv
      python-frontmatter
      cryptography
      requests
      feedparser
    ]);

  personalWebsiteSyncScript = pkgs.writeShellScript "personal-website-sync" ''
    set -euo pipefail

    project_dir="${config.home.homeDirectory}/Projects/website"
    data_dir="$project_dir/data-processing"

    cd "$data_dir"

    if [ -f .env ]; then
      set -a
      . ./.env
      set +a
    fi

    export NIXPKGS_ALLOW_UNFREE=1

    echo "Starting Website Sync at $(date)"

    # Offline runs used to exit 1: launchd starts the job on wake (a StartInterval
    # that came due during sleep), often before the network is back, and nix-shell
    # then can't fetch <nixpkgs> while pymongo can't resolve the cluster's SRV
    # record (err-personal-website-sync-20261022-092020). Wait for that record to
    # answer; if it never does, skip and let the next hourly run sync. NXDOMAIN
    # means DNS works, so a missing cluster still fails loudly in pymongo.
    # (/usr/bin/dig: macOS ships it, and this job only runs on the Mac.)
    if [[ ''${MONGODB_URI:-} == mongodb+srv://* ]]; then
      mongo_host=''${MONGODB_URI#*://}
      mongo_host=''${mongo_host##*@}
      mongo_host=''${mongo_host%%[/?]*}
      net_wait=''${WEBSITE_SYNC_NET_WAIT:-180}
      deadline=$(( $(date +%s) + net_wait ))
      until dns=$(/usr/bin/dig +time=3 +tries=1 SRV "_mongodb._tcp.$mongo_host" | sed -n 's/.*status: \([A-Z]*\).*/\1/p'); [[ $dns == NOERROR || $dns == NXDOMAIN ]]; do
        if (( $(date +%s) >= deadline )); then
          echo "Skipped at $(date): offline, no DNS answer for _mongodb._tcp.$mongo_host in ''${net_wait}s (last: ''${dns:-no reply}); the next hourly run will sync."
          exit 0
        fi
        [[ -n ''${waiting:-} ]] || { echo "No DNS answer for _mongodb._tcp.$mongo_host (''${dns:-no reply}); waiting up to ''${net_wait}s for the network."; waiting=1; }
        sleep 10
      done
    fi

    ${websiteSyncPython}/bin/python3 main.py --log
    echo "Sync completed at $(date)"
  '';
in {
  config =
    # tw-gcal-sync disabled — syncall uses taskw-ng which reads TW2 data files
    # directly and is incompatible with TW3's SQLite storage.
    # TODO: find TW3-compatible calendar sync solution
    lib.mkMerge [
      (scheduled {
        name = "second-brain-automation";
        description = "Run Beeper sync and PARA automation on a timer";
        # Was /etc/profiles/per-user/matth/bin/python3 — the same interpreter, but
        # by a path that only exists on NixOS. The store path is identical on both
        # platforms and immune to profile churn.
        command = ["${pkgs.python3}/bin/python3" "${vaultDir}/scripts/second-brain-automation.py"];
        linuxPathEntries = ["/etc/profiles/per-user/matth/bin" "/run/current-system/sw/bin"];

        onBootSec = "5m";
        onUnitActiveSec = "10m";
        persistent = true;
        timerUnit = "second-brain-automation.service";
        timerDescription = "Timer for second-brain-automation (every 10 minutes)";
        everySeconds = 600;

        # Path watcher: trigger automation immediately when captures change
        # (complements the 10-minute timer with instant processing)
        watchPaths = [
          "${notesDir}/capture/raw_capture"
          "${notesDir}/resources"
        ];
        pathsName = "para-automation-watcher";
        pathsDescription = "Watch capture directory for new files";
        pathsExtra = {
          # Debounce: don't trigger more than once per 30 seconds
          MakeDirectory = true;
        };

        # nix + bash: the script hands off to the vault's beeper/run_sync.sh,
        # which shells out to `nix-shell`. A LaunchAgent's PATH has none of the
        # profile dirs that supply it, so without these the Mac side fails with
        # "nix-shell: command not found" the moment the script path is right.
        path = [pkgs.python3 pkgs.coreutils pkgs.git pkgs.nix pkgs.bash];
        # Pin <nixpkgs> for that nix-shell to this flake's locked nixpkgs (a local
        # store path). Without it, <nixpkgs> came from Determinate's nix.conf
        # nix-path: a floating flakehub tarball re-fetched every hour, so every
        # pass with DNS down exited 1 ("Could not resolve host: flakehub.com",
        # 45 times by 2026-11-10; bug err-second-brain-automation-20261110-103425).
        environment.NIX_PATH = "nixpkgs=${pkgs.path}";
        logFile = "%h/.local/state/second-brain-automation.log";
      })

      (scheduled {
        name = "focus-reflection-reminder";
        description = "Send an hourly focus/reflection reminder";
        # notify-send's -t/-u have no terminal-notifier equivalent, and folding
        # them into the shared `notify` shim would quietly change every other
        # caller. So the Linux argv stays exactly what it was (10s, normal
        # urgency) and only the Mac goes through the shim.
        command =
          if isDarwin
          then [
            "${notify}/bin/notify"
            "Focus check"
            "Make sure you're focused on a task and have done your reflection for it!"
          ]
          else [
            "${pkgs.libnotify}/bin/notify-send"
            "-t"
            "10000"
            "-u"
            "normal"
            "Focus check"
            "Make sure you're focused on a task and have done your reflection for it!"
          ];

        onBootSec = "5m";
        onUnitActiveSec = "1h";
        persistent = true;
        timerUnit = "focus-reflection-reminder.service";
        timerDescription = "Timer for focus/reflection reminder";
        everySeconds = 3600;

        path = [notify];
      })

      # taskwarrior-export: retired 2026-10-25 (Matt no longer uses Taskwarrior;
      # it fed the server's "Task export stale" push).

      # Mac only. Two hosts running this is destructive, not redundant: each
      # run's prune_missing_content_file_documents deletes every content row
      # whose metadata.file_path does not exist on *that* host, so the laptop
      # (/home/matth/...) and the Mac (/Users/matth/...) deleted each other's
      # rows every hour. On 2026-10-11 every blog post on the site 404'd.
      (lib.optionalAttrs isDarwin (scheduled {
        name = "personal-website-sync";
        description = "Sync Obsidian Vault to Personal Website MongoDB";
        command = ["${pkgs.bash}/bin/bash" "${personalWebsiteSyncScript}"];

        # Home Manager activation runs `systemctl --user start/stop` on managed
        # units during `reloadSystemd`. This is a long-running oneshot (can build
        # large deps like MongoDB), so starting it during activation makes
        # `nixos-rebuild switch` appear to "freeze" and often times out.
        #
        # The timer can still start it (dependency activation), but manual starts
        # during HM activation are refused. Deliberately NOT enabled on
        # default.target for the same reason.
        after = ["network.target"];

        onBootSec = "5min";
        onUnitActiveSec = "1h";
        timerUnit = "personal-website-sync.service";
        timerDescription = "Run Website Sync every hour";
        everySeconds = 3600;

        workingDirectory = "${config.home.homeDirectory}/Projects/website/data-processing";
        linuxLogFile = "${config.home.homeDirectory}/Projects/website/sync.log";
        logFile = "${config.home.homeDirectory}/Projects/website/sync.log";
        # A full run writes ~1.2 MB now (was 56 MB before pymongo's wire log was
        # silenced); 50 MB keeps about two days of hourly runs per generation.
        logMaxBytes = 50 * 1024 * 1024;
        path = [pkgs.bash pkgs.nix pkgs.coreutils];
        serviceExtra.StandardError = "append:${config.home.homeDirectory}/Projects/website/sync.error.log";
        # Not scheduled.nix's Background: launchd's background clamp throttles
        # the job's I/O while Matt is active, and a cold run (nix-shell copying
        # all of nixpkgs into the store whenever nixpkgs-weekly moves) sat at
        # 10 s of CPU in 25 min; the same evaluation took 108 s at normal
        # priority (Oops 20261015-175208). Matt also starts it on demand from
        # Raycast ("Vault → Website Sync") and waits on it.
        launchdExtra.ProcessType = "Standard";
      }))

      # birthday-check removed (off 2026-11-15: Matt asked to delete the ntfy senders); scripts/birthday-manager.py is still in the vault.

      # inject-experiment-questions — idempotently inject experiment-declared
      # questions into today's daily note. Same story: hand-enabled on the laptop,
      # now declared once for both platforms.
      (scheduled {
        name = "inject-experiment-questions";
        description = "Inject experiment-declared questions into today's daily note (idempotent)";
        command = ["${config.home.homeDirectory}/Obsidian/Main/scripts/inject-experiment-questions.sh"];
        # the script defaults VAULT to /home/matth/…; spell it out so the Mac works
        environment.VAULT = "%h/Obsidian/Main";
        after = ["graphical-session.target"];
        onBootSec = "2min";
        onUnitActiveSec = "30min";
        persistent = true;
        timerDescription = "Inject experiment questions into today's daily note (every 30 min)";
        everySeconds = 1800;
        path = [pkgs.bash pkgs.coreutils pkgs.gnused pkgs.gawk pkgs.gnugrep];
        darwinPathEntries = ["${config.home.profileDirectory}/bin" "/usr/bin" "/bin"];
        logFile = "%h/.local/state/inject-experiment-questions.log";
      })

      # If this unit was previously enabled on default.target, the symlink can stick
      # around and Home Manager activation will try to stop/start it during rebuilds.
      # Make sure it is timer-only. (systemd-only leftover; no launchd analogue.)
      (lib.optionalAttrs isLinux {
        home.activation.personalWebsiteSyncCleanup = lib.hm.dag.entryAfter ["writeBoundary"] ''
          rm -f "$HOME/.config/systemd/user/default.target.wants/personal-website-sync.service"
        '';
      })
    ];
}
