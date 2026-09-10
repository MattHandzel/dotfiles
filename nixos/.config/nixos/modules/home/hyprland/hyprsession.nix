{
  config,
  pkgs,
  ...
}: let
  # Own derivation (same source as the scripts.nix copy) so the systemd
  # service can reference a store path directly.
  sessionSave =
    pkgs.writeShellScriptBin "hyprland-session-save"
    (builtins.readFile ../scripts/scripts/hyprland-session-save.sh);
in {
  # Periodic snapshot of open windows -> ~/.local/state/hyprland-session/session.json
  # Restore on demand with `hyprland-session-restore` (modules/home/scripts).
  systemd.user.services.hyprland-session-save = {
    Unit = {
      Description = "Snapshot Hyprland session (windows, workspaces, terminal cwds)";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${sessionSave}/bin/hyprland-session-save";
      Environment = [
        "PATH=/run/current-system/sw/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/matth/bin"
      ];
    };
  };

  systemd.user.timers.hyprland-session-save = {
    Unit = {
      Description = "Snapshot Hyprland session every 2 minutes";
    };
    Timer = {
      OnStartupSec = "2min";
      OnUnitActiveSec = "2min";
      Unit = "hyprland-session-save.service";
    };
    Install = {
      WantedBy = ["timers.target"];
    };
  };
}
