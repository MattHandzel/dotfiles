# /home/matth/dotfiles/nixos/.config/nixos/modules/core/notify-poller.nix
#
# Mongo→ntfy bridge for visitor messages + signups.
#
# Variant of notify-poller.nix.example that does NOT depend on sops-nix —
# this server doesn't have sops wired into the flake yet. Secrets are
# loaded from a user-owned EnvironmentFile at:
#
#     /home/matth/.config/notify-poller/secrets.env   (mode 0600)
#
# That file must contain:
#     MONGODB_URI="mongodb+srv://..."
#     RESEND_API_KEY="re_..."
#
# When sops gets set up later, swap this module for the .example variant.

{ pkgs, ... }:

let
  user = "matth";
  websiteDir = "/home/${user}/Projects/website";
  pollerDir = "${websiteDir}/data-processing/notify-poller";
  venvPython = "${websiteDir}/data-processing/.venv/bin/python";
  envFile = "/home/${user}/.config/notify-poller/secrets.env";

  # NixOS quirk: the venv interpreter is dynamically linked against
  # libstdc++ from the toolchain that built it; that .so isn't on the
  # default LD path, so we point at it explicitly.
  ccLib = "${pkgs.stdenv.cc.cc.lib}/lib";
in
{
  systemd.services."notify-poller" = {
    description = "Mongo→ntfy poller for website visitor messages + signups";
    serviceConfig = {
      Type = "oneshot";
      User = user;
      WorkingDirectory = pollerDir;
      EnvironmentFile = envFile;
      RuntimeDirectory = "notify-poller";
      Environment = [
        "PATH=${pkgs.coreutils}/bin:${pkgs.bash}/bin"
        "MONGODB_DB=website_db"
        "NTFY_URL=http://localhost:8124/website-messages"
        "NOTIFY_PIDFILE=/run/notify-poller/notify-poller.pid"
        "LD_LIBRARY_PATH=${ccLib}"
      ];
      ExecStart = pkgs.writeShellScript "notify-poller-run" ''
        set -euo pipefail
        exec ${venvPython} ${pollerDir}/poll.py
      '';

      # Filesystem hardening
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ pollerDir ];
      PrivateTmp = true;

      NoNewPrivileges = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictNamespaces = true;
      SystemCallArchitectures = "native";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];

      MemoryMax = "256M";
      CPUQuota = "50%";
      TimeoutStartSec = "60s";

      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "notify-poller";
    };
  };

  systemd.timers."notify-poller" = {
    description = "Mongo→ntfy poller — 90s cadence";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "90s";
      AccuracySec = "10s";
      Persistent = true;
      Unit = "notify-poller.service";
    };
  };

  # ---------------------------------------------------------------------------
  # Weekly heartbeat — Sunday 09:00 canary + audit summary
  # ---------------------------------------------------------------------------

  systemd.services."notify-poller-heartbeat" = {
    description = "Weekly heartbeat + audit summary for the Mongo→ntfy poller";
    serviceConfig = {
      Type = "oneshot";
      User = user;
      WorkingDirectory = pollerDir;
      EnvironmentFile = envFile;
      RuntimeDirectory = "notify-poller-heartbeat";
      Environment = [
        "PATH=${pkgs.coreutils}/bin:${pkgs.bash}/bin"
        "MONGODB_DB=website_db"
        "NTFY_URL=http://localhost:8124/website-messages"
        "NOTIFY_PIDFILE=/run/notify-poller-heartbeat/notify-poller-heartbeat.pid"
        "EMAIL_NOTIFY_TO=matt@matthandzel.com"
        "RESEND_FROM=notify-poller@matthandzel.com"
        "LD_LIBRARY_PATH=${ccLib}"
      ];
      ExecStart = pkgs.writeShellScript "notify-poller-heartbeat-run" ''
        set -euo pipefail
        exec ${venvPython} ${pollerDir}/poll.py --heartbeat
      '';

      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = [ pollerDir ];
      PrivateTmp = true;

      NoNewPrivileges = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictNamespaces = true;
      SystemCallArchitectures = "native";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];

      MemoryMax = "256M";
      CPUQuota = "50%";
      TimeoutStartSec = "60s";

      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "notify-poller-heartbeat";
    };
  };

  systemd.timers."notify-poller-heartbeat" = {
    description = "Fire notify-poller-heartbeat every Sunday 09:00 server-local";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 09:00";
      AccuracySec = "1m";
      Persistent = true;
      Unit = "notify-poller-heartbeat.service";
    };
  };
}
