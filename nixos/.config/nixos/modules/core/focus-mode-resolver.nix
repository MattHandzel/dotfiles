# System-Wide Focus — calendar-driven mode resolver (Phase 2).
#
# Runs on the server every 60s, co-located with blocky (focus-dns.nix). Reads the
# Life Scheduler calendar, maps the active block to a mode, reconciles blocky's
# deny-list, and publishes mode transitions to ntfy for the desktop focus-guard.
# Mirrors gmail-automation.nix (Python service + systemd timer, runs as matth).
{pkgs, ...}: let
  # Google client libs, reproducibly — no pip, no ~/.local.
  pythonEnv = pkgs.python3.withPackages (ps:
    with ps; [
      google-auth
      google-auth-oauthlib
      google-api-python-client
    ]);

  resolverPath = "/home/matth/Projects/system-wide-focus/resolver/resolver.py";

  runResolver = pkgs.writeShellScript "focus-mode-resolver-run" ''
    exec ${pythonEnv}/bin/python3 ${resolverPath}
  '';
in {
  # token.json lives here (scp'd from the laptop after the one-time authorize.py consent).
  systemd.tmpfiles.rules = [
    "d /home/matth/.config/focus-mode-resolver 0700 matth users -"
  ];

  systemd.services.focus-mode-resolver = {
    description = "System-Wide Focus — calendar-driven mode resolver";
    after = ["network-online.target" "blocky.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      # HOME so the resolver finds ~/.config/focus-mode-resolver/token.json.
      Environment = ["HOME=/home/matth"];
      ExecStart = "${runResolver}";
      # 0 ok, 2 = missing/invalid token (don't spam logs; next tick retries).
      SuccessExitStatus = "0 2";
    };
  };

  systemd.timers.focus-mode-resolver = {
    description = "Run the focus-mode resolver every minute";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* *:*:00";
      Persistent = true;
      Unit = "focus-mode-resolver.service";
    };
  };
}
