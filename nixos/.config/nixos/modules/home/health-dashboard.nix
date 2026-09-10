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
  # Where the health-data-dashboard pipeline lives. The importer itself
  # (refresh.sh = pull.py [Google Sheet -> parquet] -> render.py -> the vault
  # digest) is part of *that* project, not the dotfiles — this module only
  # schedules it. See projects/health-data-dashboard/SPEC.md item 5.
  projectDir = "${config.home.homeDirectory}/Projects/health-data-dashboard";

  # Loud-alert endpoint. Mirrors the dashboard's own anomaly push (SPEC AC-11).
  # The whole point of this timer is to turn the silent multi-week staleness
  # failure into either a fresh dashboard or a visible ping.
  ntfyUrl = "http://server.matthandzel.com:8124/claude";

  refreshScript = pkgs.writeShellScript "health-dashboard-refresh" ''
    set -uo pipefail

    project_dir="${projectDir}"
    log() { printf '%s %s\n' "$(${pkgs.coreutils}/bin/date -Is)" "$*"; }

    # POST one line to ntfy; never let a notification failure mask the real
    # exit status (|| true).
    notify() {
      ${pkgs.curl}/bin/curl -fsS \
        -H "Title: Health dashboard" \
        -H "Tags: health-dashboard" \
        -d "$1" "${ntfyUrl}" >/dev/null 2>&1 || true
    }

    host="$(${pkgs.coreutils}/bin/uname -n)"

    # Code-missing path: alert loudly instead of silently doing nothing. This is
    # the failure mode this issue exists to kill — blindness must never be quiet.
    if [ ! -e "$project_dir/refresh.sh" ]; then
      log "ERROR: $project_dir/refresh.sh not found on $host — health data is BLIND."
      notify "Health import did NOT run: refresh.sh missing at $project_dir on $host. Dashboard is going stale."
      exit 1
    fi

    cd "$project_dir" || {
      notify "Health import did NOT run: cannot cd into $project_dir on $host."
      exit 1
    }

    # Project-local secrets (Google Drive OAuth token path, etc.) live in .env,
    # mirroring the gdoc-sync / personal-website-sync pattern.
    if [ -f .env ]; then
      set -a
      . ./.env
      set +a
    fi

    log "Starting health-dashboard refresh"
    # The project's shell.nix provides python + pandas/plotly/google-api deps
    # (SPEC tech stack). Run inside it when present; otherwise trust refresh.sh
    # to provision its own environment.
    if [ -f shell.nix ]; then
      ${pkgs.nix}/bin/nix-shell shell.nix --run "bash ./refresh.sh"
    else
      bash ./refresh.sh
    fi
    status=$?

    if [ "$status" -ne 0 ]; then
      log "ERROR: refresh.sh exited $status"
      notify "Health import FAILED (exit $status) on $host — dashboard not updated. Check: journalctl --user -u health-dashboard-refresh"
      exit "$status"
    fi

    log "health-dashboard refresh completed"
  '';
  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  config = scheduled {
    name = "health-dashboard-refresh";
    description = "Refresh the multi-source health-data dashboard (pull -> render)";
    command = ["${pkgs.bash}/bin/bash" "${refreshScript}"];

    after = ["network.target"];

    onCalendar = "*-*-* 09:00:00";
    # CRITICAL: the laptop is routinely asleep/off at 09:00. Persistent makes
    # systemd run the most recent missed trigger on the next boot/login, so the
    # import can't silently skip for days — the exact failure this issue fixes.
    persistent = true;
    timerUnit = "health-dashboard-refresh.service";
    timerDescription = "Daily 09:00 health-dashboard refresh (Persistent: a missed run fires on next boot)";

    # launchd runs a missed StartCalendarInterval job when the Mac next wakes,
    # which is the Persistent behaviour above.
    startCalendarInterval = [
      {
        Hour = 9;
        Minute = 0;
      }
    ];
    path = [pkgs.bash pkgs.coreutils pkgs.curl pkgs.nix];
    logFile = "%h/.local/state/health-dashboard-refresh.log";

    serviceExtra = {
      # Heavy pandas/plotly run — stay out of the way of interactive work.
      IOSchedulingClass = "idle";
      CPUSchedulingPolicy = "idle";
    };
    # macOS equivalent of the idle IO/CPU scheduling above.
    launchdExtra = {
      Nice = 10;
      LowPriorityIO = true;
    };
  };
}
