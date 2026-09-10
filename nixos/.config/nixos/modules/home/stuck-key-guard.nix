# Fixes the "Shift/Super/Ctrl is stuck down" bug that arrived with Wispr Flow.
#
# Wispr types through a uinput keyboard ("Wispr Flow Linux Helper"): modifier
# down, characters, modifier up. When that burst is interrupted the key-up is
# never sent, so the key stays down on the *device* and the compositor latches
# the modifier — nothing is physically held, so no amount of real typing clears
# it. The guard injects the missing key-up into the offending device node.
#
# It only ever writes to virtual (uinput) keyboards, and never while a physical
# key is down — see the script's docstring for why that makes it safe against
# kanata's home-row mods. Runs as the user: /dev/input is root:input group-write
# and matth is in `input`.
#
# Manual escape hatch: `stuck-key-guard --now` releases everything immediately.
# Logs: journalctl --user -u stuck-key-guard -f
{pkgs, ...}: let
  stuck-key-guard = pkgs.writeShellScriptBin "stuck-key-guard" ''
    exec ${pkgs.python3}/bin/python3 ${./scripts/scripts/stuck-key-guard.py} "$@"
  '';
in {
  home.packages = [stuck-key-guard];

  systemd.user.services.stuck-key-guard = {
    Unit = {
      Description = "Release keys stranded on virtual keyboards (Wispr Flow stuck-modifier bug)";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${stuck-key-guard}/bin/stuck-key-guard";
      Environment = ["PATH=${pkgs.lib.makeBinPath [pkgs.libnotify pkgs.coreutils]}"];
      Restart = "always";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
