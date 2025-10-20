{ pkgs, lib, ... }:
let
  espansoPkg = pkgs.espanso-wayland;
in {
  # Run espanso as a user service pointing at the packaged binary.
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
