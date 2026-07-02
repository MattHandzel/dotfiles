{
  config,
  lib,
  pkgs,
  ...
}: let
  electronRestart = pkgs.writeShellApplication {
    name = "electron-app-daily-restart";
    runtimeInputs = with pkgs; [coreutils procps systemd];
    bashOptions = ["nounset"];
    text = ''
      LOG_DIR="$HOME/.local/state/electron-restart"
      mkdir -p "$LOG_DIR"
      LOG="$LOG_DIR/restart.log"

      log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

      restart_app() {
        local name="$1" pattern="$2" launch_bin="$3"
        local pids launch_path unit_name
        pids=$(pgrep -f "$pattern" 2>/dev/null || true)
        if [ -z "$pids" ]; then
          log "$name: not running, skipping"
          return 0
        fi
        log "$name: TERM-ing PIDs $(echo "$pids" | tr '\n' ' ')"
        pkill -TERM -f "$pattern" 2>/dev/null || true
        sleep 5
        pkill -KILL -f "$pattern" 2>/dev/null || true
        sleep 2
        launch_path=$(command -v "$launch_bin" 2>/dev/null || true)
        if [ -z "$launch_path" ]; then
          log "$name: launcher '$launch_bin' not in PATH, NOT relaunched"
          return 0
        fi
        unit_name="$name-relaunch-$(date +%s)"
        log "$name: relaunching as $unit_name with $launch_path"
        # systemd-run --no-block creates a transient service so the relaunched
        # app survives this oneshot exiting; --slice=app.slice keeps it grouped
        # with other graphical apps.
        if systemd-run --user --no-block --slice=app.slice \
          --unit="$unit_name" -- "$launch_path" >>"$LOG" 2>&1; then
          log "$name: systemd-run dispatched"
        else
          log "$name: systemd-run failed"
        fi
      }

      # Match by exec path so we don't accidentally kill unrelated processes
      # whose cmdline happens to contain 'discord' or 'slack' as a substring.
      restart_app "discord" "/Discord/" "discord"
      # Slack auto-relaunch removed (2026-07): Beeper bridges Slack, so keeping a
      # second always-on Slack client wasted ~170MB on a RAM-tight 16GB machine.
      # This relaunch also landed Slack in app.slice, bypassing the app-slack.slice
      # memory cap. The SUPER+ALT+K launcher still opens Slack on demand.
      # restart_app "slack" "/slack/" "slack"
      log "done"
    '';
  };
in {
  systemd.user.tmpfiles.rules = [
    "d %h/.local/state/electron-restart 0700 - - - -"
  ];

  systemd.user.services.electron-app-daily-restart = {
    Unit = {
      Description = "Daily silent restart of Electron messaging apps (Discord, Slack)";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${electronRestart}/bin/electron-app-daily-restart";
      Environment = [
        "PATH=/run/current-system/sw/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/matth/bin"
      ];
    };
  };

  systemd.user.timers.electron-app-daily-restart = {
    Unit = {
      Description = "Daily 04:00 trigger for Electron-app restart";
    };
    Timer = {
      OnCalendar = "04:00:00";
      # Persistent=false: if laptop is asleep at 04:00, the missed firing is
      # dropped rather than caught up on wake — catching up would kill apps
      # mid-morning and defeat the "silent" property.
      Persistent = false;
      Unit = "electron-app-daily-restart.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}
