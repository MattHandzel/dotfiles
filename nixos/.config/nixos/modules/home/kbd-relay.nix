# Makes Wispr Flow see the Bluetooth TOTEM, without ever restarting Wispr.
#
# Wispr enumerates evdev keyboards once at startup and never watches udev, so a
# keyboard connected later is invisible to it forever. Rather than force Wispr to
# rescan (it could be mid-recording), this creates ONE virtual keyboard at login —
# present before Wispr starts, and never removed — and forwards the TOTEM through
# it verbatim. Wispr watches a device that never goes away.
#
# Verbatim matters: routing the TOTEM through kanata instead (tried 2026-07-14)
# mangled keys the TOTEM firmware had already remapped. This relay does no
# remapping. See modules/home/scripts/scripts/kbd-relay.py.
#
# Logs: journalctl --user -u kbd-relay -f
{pkgs, ...}: let
  kbd-relay = pkgs.writeShellScriptBin "kbd-relay" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/scripts/kbd-relay.py} "$@"
  '';
in {
  home.packages = [kbd-relay];

  systemd.user.services.kbd-relay = {
    Unit = {
      Description = "Relay hot-plugged keyboards through an always-present virtual keyboard";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${kbd-relay}/bin/kbd-relay";
      # No Environment= for the keyboard names: a systemd Environment value can't
      # hold spaces/apostrophes as written (it word-splits, which silently left
      # the relay watching for "ZMK"). The target names now live as the default
      # in kbd-relay.py instead. Override at runtime with a properly-quoted
      # RELAY_KEYBOARDS if ever needed.
      Restart = "always";
      RestartSec = 5;
      # Wispr enumerates keyboards once at startup, so every (re)start of this
      # relay must bounce Wispr or it keeps watching the dead device node.
      # --no-block avoids a deadlock: wispr-flow is After= this unit, so a
      # blocking restart inside our own start job would wait on itself.
      # try-restart is a no-op at login when Wispr isn't running yet.
      ExecStartPost = "${pkgs.systemd}/bin/systemctl --user --no-block try-restart wispr-flow.service";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
