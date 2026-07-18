{
  pkgs,
  lib,
  ...
}: let
  espansoPkg = pkgs.espanso-wayland;
in {
  # Point at the packaged binary directly. `espanso restart` will refuse
  # because /proc/self/exe (via the suid wrapper chain) doesn't match
  # ExecStart — use `systemctl --user restart espanso` instead. Input access
  # comes from the `input` group, not the suid wrapper's capabilities.
  systemd.user.services.espanso = {
    Unit = {
      Description = "Espanso text expander";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = lib.mkForce "${espansoPkg}/bin/espanso daemon";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };
}
