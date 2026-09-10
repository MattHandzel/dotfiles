# System-Wide Focus — laptop/desktop focus-state agent.
#
# A device-local "what am I supposed to be doing right now" service. Reads the current
# Life Scheduler event + category (directly, every 30s) and writes it to
# ~/.local/state/focus/current.json. Laptop-side modes (waybar indicator, single-tasking
# guard, pre-load, grayscale, …) read that file and react. The general primitive Matt
# asked for. DNS enforcement stays server-side; this is the device-side awareness layer.
#
# Runs as matth (like gmail-automation) with the same gcal read-only token. Import on
# the laptop/desktop hosts (not the server — the server has the resolver).
{pkgs, ...}: let
  pythonEnv = pkgs.python3.withPackages (ps:
    with ps; [
      google-auth
      google-auth-oauthlib
      google-api-python-client
    ]);
  agentPath = "/home/matth/Projects/system-wide-focus/resolver/laptop_agent.py";
  runAgent = pkgs.writeShellScript "focus-state-agent-run" ''
    exec ${pythonEnv}/bin/python3 ${agentPath}
  '';
in {
  systemd.services.focus-state-agent = {
    description = "System-Wide Focus — device-local current-event/category awareness";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      Environment = ["HOME=/home/matth"];
      ExecStart = "${runAgent}";
      SuccessExitStatus = "0 2"; # 2 = missing/invalid token (graceful)
    };
  };

  systemd.timers.focus-state-agent = {
    description = "Refresh focus-state every 2min (fast first read at boot, then relaxed to cut Python+API spawns)";
    wantedBy = ["timers.target"];
    timerConfig = {
      # Fast first read after boot; relaxed steady-state — each tick spins up a
      # full Python interpreter + Google API client + network call, so 30s was
      # the most expensive recurring wakeup on the laptop. A calendar edit now
      # reflects in ≤2min, which is plenty for a waybar/grayscale awareness layer.
      OnBootSec = "30s";
      OnUnitActiveSec = "2min";
      Persistent = true;
      Unit = "focus-state-agent.service";
    };
  };
}
