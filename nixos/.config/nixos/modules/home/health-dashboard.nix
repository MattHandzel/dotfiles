{
  config,
  lib,
  pkgs,
  ...
}: let
  readinessBin = pkgs.writeShellApplication {
    name = "readiness";
    runtimeInputs = with pkgs; [coreutils python311];
    bashOptions = ["nounset"];
    text = ''
      exec ${pkgs.python311}/bin/python3 "$HOME/Projects/health-data-dashboard/bin/readiness" "$@"
    '';
  };

  refreshWrapper = pkgs.writeShellApplication {
    name = "health-dashboard-refresh";
    runtimeInputs = with pkgs; [coreutils nix bash];
    bashOptions = ["nounset"];
    text = ''
      LOG_DIR="$HOME/.local/state/health-dashboard"
      mkdir -p "$LOG_DIR"
      LOG="$LOG_DIR/refresh.log"

      log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

      REPO="$HOME/Projects/health-data-dashboard"
      if [ ! -d "$REPO" ]; then
        log "ERROR: $REPO not found"
        exit 1
      fi

      cd "$REPO" || { log "ERROR: cd $REPO failed"; exit 1; }
      log "starting refresh.sh"
      if ./refresh.sh --quiet >> "$LOG" 2>&1; then
        log "ok"
      else
        log "FAILED with exit $?"
        exit 1
      fi
    '';
  };
in {
  home.packages = [readinessBin];

  systemd.user.tmpfiles.rules = [
    "d %h/.local/state/health-dashboard 0700 - - - -"
  ];

  systemd.user.services.health-dashboard-refresh = {
    Unit = {
      Description = "Health Data Dashboard refresh (Google Sheet → dashboard.html + LLM digest)";
      After = ["network-online.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${refreshWrapper}/bin/health-dashboard-refresh";
      Environment = [
        "PATH=/run/current-system/sw/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/matth/bin"
      ];
    };
  };

  systemd.user.timers.health-dashboard-refresh = {
    Unit = {
      Description = "Daily 09:00 trigger for health-dashboard refresh";
    };
    Timer = {
      OnCalendar = "09:00:00";
      # Persistent=true: if laptop was off at 09:00, run on next wake.
      # Daily health summary is still useful even if it's an hour late.
      Persistent = true;
      Unit = "health-dashboard-refresh.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}
