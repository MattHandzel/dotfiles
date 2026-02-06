{
  config,
  lib,
  pkgs,
  ...
}: let
  syncall = pkgs.callPackage ../../pkgs/syncall/default.nix {};
  twGcalSyncDir = "${config.home.homeDirectory}/.local/share/tw-gcal-sync";
  twGcalSyncScript = pkgs.writeShellScript "tw_gcal_sync_script" ''
    set -euo pipefail
    tw_gcal_sync_dir=${lib.escapeShellArg twGcalSyncDir}
    # if the directory doesn't exist
    if [ ! -d "$tw_gcal_sync_dir" ]; then
      echo "tw-gcal-sync directory not found at $tw_gcal_sync_dir"
      mkdir -p "$tw_gcal_sync_dir"
    fi

    ${syncall}/bin/tw_gcal_sync -c "Taskwarrior" -f due.any: -f status:pending --only-modified-last-X-days 1 --prefer-scheduled-date --default-event-duration-mins 60 --google-secret /run/secrets/gcal_client_secret
  '';
  notesDir = "${config.home.homeDirectory}/notes";
  automationScript = "${config.home.homeDirectory}/Projects/KnowledgeManagementSystem/organize/scripts/systemd/para-automation.sh";
  lockDir = "${config.home.homeDirectory}/.local/state/para-automation";
  watcherScript = pkgs.writeShellScript "para-automation-watcher" ''
    set -euo pipefail

    notes_dir=${lib.escapeShellArg notesDir}
    lock_dir=${lib.escapeShellArg lockDir}

    mkdir -p "$lock_dir"
    lock_file="$lock_dir/watcher.lock"

    while true; do
      ${pkgs.inotify-tools}/bin/inotifywait -r -q \
        -e close_write -e create -e moved_to -e moved_from -e delete "$notes_dir" || continue

      ${pkgs.util-linux}/bin/flock "$lock_file" -c ${lib.escapeShellArg "${pkgs.bash}/bin/bash ${automationScript}"} || true

      while ${pkgs.inotify-tools}/bin/inotifywait -r -q -t 1 \
        -e close_write -e create -e moved_to -e moved_from -e delete "$notes_dir"; do
        :
      done
    done
  '';
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
  systemd.user.services.tw-gcal-sync = {
    Unit = {
      Description = "Sync taskwarrior with Google Calendar";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${twGcalSyncScript}";
    };
  };

  systemd.user.timers.tw-gcal-sync = {
    Unit = {
      Description = "Timer for tw-gcal-sync service";
    };
    Timer = {
      OnBootSec = "10m";
      OnUnitActiveSec = "15m";
      Persistent = true;
      Unit = "tw-gcal-sync.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };

  systemd.user.services.para-automation = {
    Unit = {
      Description = "Run PARA automation after notes updates";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${automationScript}";
    };
  };

  systemd.user.services."para-automation-watcher" = {
    Unit = {
      Description = "Watch the notes directory for updates";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Environment = ["PATH=/run/current-system/sw/bin"];
      ExecStart = watcherScript;
      Restart = "always";
      RestartSec = 3;
    };
    Install = {
      WantedBy = ["default.target"];
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
      RefuseManualStart = true;
      RefuseManualStop = true;
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
