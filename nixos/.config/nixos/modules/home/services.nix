{
  config,
  lib,
  pkgs,
  ...
}: let
  twGcalSyncDir = "${config.home.homeDirectory}/.local/share/tw-gcal-sync";
  twGcalSyncScript = pkgs.writeShellScript "tw_gcal_sync_script" ''
      set -euo pipefail
      tw_gcal_sync_dir=${lib.escapeShellArg twGcalSyncDir}
      # if the directory doesn't exist
      if [ ! -d "$tw_gcal_sync_dir" ]; then
        echo "tw-gcal-sync directory not found at $tw_gcal_sync_dir"

        mkdir -p "$tw_gcal_sync_dir"
        if [ ! -f "${lib.escapeShellArg config.home.homeDirectory}/secrets/gcal_client_secret.json" ]; then
          echo "Google client secret not found at ${lib.escapeShellArg config.home.homeDirectory}/secrets/gcal_client_secret.json"
          exit 1
        fi
        cp "${lib.escapeShellArg config.home.homeDirectory}/secrets/gcal_client_secret.json" "$tw_gcal_sync_dir/gcal_client_secret.json"
      fi

      cd $tw_gcal_sync_dir;
      if [ ! -d ".venv" ]; then
        ${pkgs.python3}/bin/python3 -m venv .venv
      fi

      source .venv/bin/activate
      # Activate the virtual environment
      if ! pip show syncall; then
        python -m pip install --upgrade pip
        .venv/bin/pip install "syncall[google,tw]" taskwarrior-syncall
      fi


    .venv/bin/tw_gcal_sync -c "Taskwarrior" -f due.any: -f status:pending --only-modified-last-X-days 1 --prefer-scheduled-date --default-event-duration-mins 60 --google-secret ./gcal_client_secret.json
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
      ${pkgs.inotifyTools}/bin/inotifywait -r -q \
        -e close_write -e create -e moved_to -e moved_from -e delete "$notes_dir" || continue

      ${pkgs.util-linux}/bin/flock "$lock_file" -c ${lib.escapeShellArg "${pkgs.bash}/bin/bash ${automationScript}"} || true

      while ${pkgs.inotifyTools}/bin/inotifywait -r -q -t 1 \
        -e close_write -e create -e moved_to -e moved_from -e delete "$notes_dir"; do
        :
      done
    done
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
}
