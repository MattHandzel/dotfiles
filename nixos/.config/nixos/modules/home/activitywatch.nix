{
  inputs,
  pkgs,
  ...
}: let
  # aw-server, aw-watcher-afk and the generic aw-watcher-window all ship in the
  # `activitywatch` package (already on PATH via packages.nix).
  aw = pkgs.activitywatch;
  # Hyprland-native window watcher (real titles) — see flake input.
  hyprWatcher = inputs.aw-watcher-window-hyprland.packages.${pkgs.system}.aw-watcher-window-hyprland;
in {
  # ActivityWatch as durable systemd USER services, replacing the ad-hoc
  # Hyprland exec-once launches (which died on logout and, for the generic
  # window watcher, logged "unknown" titles on Wayland). aw-server holds the
  # local time-tracking DB at ~/.local/share/activitywatch/aw-server-rust;
  # watchers post events to it over localhost:5600.
  #
  # The watchers need the Wayland/Hyprland session env (WAYLAND_DISPLAY,
  # HYPRLAND_INSTANCE_SIGNATURE, XDG_RUNTIME_DIR). Hyprland imports the whole
  # environment into the systemd user manager on startup
  # (wayland.windowManager.hyprland.systemd.variables = ["--all"] +
  # `systemctl --user import-environment`), so any unit ordered After
  # graphical-session.target inherits it — the same mechanism wispr-flow relies
  # on (modules/home/wispr-flow.nix).

  home.packages = [hyprWatcher];

  # aw-server is session-independent: bind it to default.target so the DB is up
  # as soon as the user manager starts, before any watcher.
  systemd.user.services.aw-server = {
    Unit = {
      Description = "ActivityWatch server (aw-server-rust), localhost:5600";
    };
    Service = {
      ExecStart = "${aw}/bin/aw-server";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = ["default.target"];
  };

  systemd.user.services.aw-watcher-afk = {
    Unit = {
      Description = "ActivityWatch AFK (idle/active) watcher";
      After = ["graphical-session.target" "aw-server.service"];
      Wants = ["aw-server.service"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${aw}/bin/aw-watcher-afk";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  systemd.user.services.aw-watcher-window-hyprland = {
    Unit = {
      Description = "ActivityWatch Hyprland window watcher (real window titles)";
      After = ["graphical-session.target" "aw-server.service"];
      Wants = ["aw-server.service"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${hyprWatcher}/bin/aw-watcher-window-hyprland";
      # The watcher shells out to `hyprctl activewindow -j` on every poll; a
      # home-manager user unit gets a minimal PATH, so without hyprctl on PATH
      # it silently logs "Failed to get active window" and posts nothing.
      Environment = ["PATH=${pkgs.lib.makeBinPath [pkgs.hyprland pkgs.coreutils]}"];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
