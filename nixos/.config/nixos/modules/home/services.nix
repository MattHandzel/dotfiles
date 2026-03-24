{
  config,
  lib,
  pkgs,
  ...
}: let
  notesDir = "${config.home.homeDirectory}/notes";
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
  # tw-gcal-sync disabled — syncall uses taskw-ng which reads TW2 data files
  # directly and is incompatible with TW3's SQLite storage.
  # TODO: find TW3-compatible calendar sync solution

  systemd.user.services.second-brain-automation = {
    Unit = {
      Description = "Run Beeper sync and PARA automation on a timer";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "/home/matth/Obsidian/Main/scripts/second-brain-automation.py";
      Environment = ["PATH=/run/current-system/sw/bin"];
    };
  };

  systemd.user.timers.second-brain-automation = {
    Unit = {
      Description = "Timer for second-brain-automation (every 10 minutes)";
    };
    Timer = {
      OnBootSec = "5m";
      OnUnitActiveSec = "10m";
      Persistent = true;
      Unit = "second-brain-automation.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };

  systemd.user.services."focus-reflection-reminder" = {
    Unit = {
      Description = "Send an hourly focus/reflection reminder";
    };
    Service = {
      Type = "oneshot";
      ExecStart = ''
        ${pkgs.libnotify}/bin/notify-send -t 10000 -u normal \
          "Focus check" "Make sure you're focused on a task and have done your reflection for it!"
      '';
    };
  };

  systemd.user.timers."focus-reflection-reminder" = {
    Unit = {
      Description = "Timer for focus/reflection reminder";
    };
    Timer = {
      OnBootSec = "5m";
      OnUnitActiveSec = "1h";
      Persistent = true;
      Unit = "focus-reflection-reminder.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };

  systemd.user.services.taskwarrior-export = {
    Unit = {
      Description = "Export Taskwarrior tasks to ShareComputer for server notifications";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${notesDir}/scripts/taskwarrior-export-due.sh";
      Environment = ["PATH=${pkgs.coreutils}/bin:${pkgs.taskwarrior3}/bin:/run/current-system/sw/bin"];
    };
  };

  systemd.user.timers.taskwarrior-export = {
    Unit = {
      Description = "Export Taskwarrior tasks every 30 minutes";
    };
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "30m";
      Persistent = true;
      Unit = "taskwarrior-export.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };

  systemd.user.services.personal-website-sync = {
    Unit = {
      Description = "Sync Obsidian Vault to Personal Website MongoDB";
      After = ["network.target"];
      # Home Manager activation runs `systemctl --user start/stop` on managed
      # units during `reloadSystemd`. This is a long-running oneshot (can build
      # large deps like MongoDB), so starting it during activation makes
      # `nixos-rebuild switch` appear to "freeze" and often times out.
      #
      # The timer can still start it (dependency activation), but manual starts
      # during HM activation are refused.
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${personalWebsiteSyncScript}";
      WorkingDirectory = "${config.home.homeDirectory}/Projects/website/data-processing";
      StandardOutput = "append:${config.home.homeDirectory}/Projects/website/sync.log";
      StandardError = "append:${config.home.homeDirectory}/Projects/website/sync.error.log";
    };
    # This is a timer-driven oneshot. Enabling it on `default.target` makes
    # Home Manager activation block while the sync runs (can take minutes),
    # causing `nixos-rebuild switch` to time out.
  };

  systemd.user.timers.personal-website-sync = {
    Unit = {
      Description = "Run Website Sync every hour";
    };
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      Unit = "personal-website-sync.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };

  # If this unit was previously enabled on default.target, the symlink can stick
  # around and Home Manager activation will try to stop/start it during rebuilds.
  # Make sure it is timer-only.
  home.activation.personalWebsiteSyncCleanup = lib.hm.dag.entryAfter ["writeBoundary"] ''
    rm -f "$HOME/.config/systemd/user/default.target.wants/personal-website-sync.service"
  '';
}
