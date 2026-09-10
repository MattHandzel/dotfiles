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
    ${pkgs.nix}/bin/nix-shell "$project_dir/shell.nix" --run "python3 main.py --log"
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

        path = [pkgs.python3 pkgs.coreutils pkgs.git];
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

      (scheduled {
        name = "taskwarrior-export";
        description = "Export Taskwarrior tasks to ShareComputer for server notifications";
        command = ["${pkgs.bash}/bin/bash" "${notesDir}/scripts/taskwarrior-export-due.sh"];
        linuxPathPackages = [pkgs.coreutils pkgs.taskwarrior3];
        linuxPathEntries = ["/run/current-system/sw/bin"];

        onBootSec = "2m";
        onUnitActiveSec = "30m";
        persistent = true;
        timerUnit = "taskwarrior-export.service";
        timerDescription = "Export Taskwarrior tasks every 30 minutes";
        everySeconds = 1800;

        path = [pkgs.bash pkgs.coreutils pkgs.taskwarrior3];
        logFile = "%h/.local/state/taskwarrior-export.log";
      })

      (scheduled {
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
        path = [pkgs.bash pkgs.nix pkgs.coreutils];
        serviceExtra.StandardError = "append:${config.home.homeDirectory}/Projects/website/sync.error.log";
      })

      # birthday-check — daily birthday check + notify from the vault. Until
      # 2026-09-10 this was a hand-`systemctl --user enable`d unit on the laptop
      # (never in the flake), so it would have been lost in the Mac migration;
      # the block below reproduces that unit exactly and adds the launchd twin.
      (scheduled {
        name = "birthday-check";
        description = "Birthday Manager - daily check and notify";
        command = ["/usr/bin/env" "python3" "%h/Obsidian/Main/scripts/birthday-manager.py" "check"];
        environment.VAULT_ROOT = "%h/Obsidian/Main";
        linuxLogFile = "%h/.local/log/birthday-manager.log";
        logFile = "%h/.local/log/birthday-manager.log";
        onCalendar = "*-*-* 07:00:00";
        persistent = true;
        timerDescription = "Run birthday check daily at 7:00 AM CT";
        startCalendarInterval = {
          Hour = 7;
          Minute = 0;
        };
        path = [pkgs.python3 pkgs.coreutils];
        darwinPathEntries = ["${config.home.profileDirectory}/bin" "/usr/bin" "/bin"];
      })

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
