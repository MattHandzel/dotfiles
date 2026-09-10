# Calendar agenda writer — feeds the waybar "now / next" slot.
#
# focus-state-agent.nix only reads the Life Scheduler group calendar, so it sees
# template blocks ("Deep work") but never real meetings, which live on the primary
# calendar. This walks every calendar the read-only token can see and writes a
# merged, conflict-ranked agenda to ~/.local/state/focus/agenda.json.
#
# Strictly additive: it does not touch focus mode, DNS, or current.json. Same token
# and same python env as focus-state-agent (gcal read-only).
{pkgs, ...}: let
  pythonEnv = pkgs.python3.withPackages (ps:
    with ps; [
      google-auth
      google-auth-oauthlib
      google-api-python-client
    ]);

  agendaPath = "/home/matth/Projects/system-wide-focus/resolver/agenda.py";

  # python puts the script's own directory on sys.path, which is how `import
  # resolver` resolves — same mechanism laptop_agent.py relies on.
  runAgenda = pkgs.writeShellScript "calendar-agenda-run" ''
    exec ${pythonEnv}/bin/python3 ${agendaPath}
  '';
in {
  systemd.services.calendar-agenda = {
    description = "Calendar agenda writer — now/next for the waybar slot";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      Environment = ["HOME=/home/matth"];
      ExecStart = "${runAgenda}";
      # 2 = missing/invalid token; the waybar module renders a "stale" state
      # rather than the bar going blank, so don't spam the journal.
      SuccessExitStatus = "0 2";
    };
  };

  systemd.timers.calendar-agenda = {
    description = "Refresh the calendar agenda every 5min";
    wantedBy = ["timers.target"];
    timerConfig = {
      # Wall-clock every 5 minutes (:00 :05 :10 …) rather than OnUnitActiveSec.
      # OnUnitActiveSec measures from when the PREVIOUS run finished, so the fetch
      # duration is added on top of the interval — measured gaps drifted to 6m51s,
      # breaking the "at least every five minutes" requirement. OnCalendar is
      # anchored to the clock, so the spacing cannot drift.
      OnCalendar = "*:0/5";
      # Default AccuracySec is 1min, which would reintroduce up to 60s of jitter.
      AccuracySec = "1s";
      # Fire immediately on resume/boot if a scheduled run was missed (laptop
      # suspend would otherwise leave the bar showing a stale event).
      Persistent = true;
      Unit = "calendar-agenda.service";
    };
  };
}
