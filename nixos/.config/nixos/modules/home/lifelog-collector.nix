{
  config,
  lib,
  ...
}: let
  home = config.home.homeDirectory;
  repoDir = "${home}/Projects/lifelog";
  authTokenEnv = "${home}/secrets/lifelog-collector.env";
in {
  # Declarative replacement of the previously hand-placed
  # ~/.config/systemd/user/lifelog-collector.service.
  #
  # The binary itself (~/Projects/lifelog/target/release/lifelog-collector) is
  # built outside this flake; the unit just wires it into systemd.
  #
  # Auto-starts with the graphical session (2026-07-15, Matt's ask: capture
  # must be persistent). Tied to graphical-session.target because screen
  # capture needs a live Wayland compositor.
  systemd.user.services.lifelog-collector = {
    Unit = {
      Description = "Lifelog Collector (user)";
      After = ["network-online.target" "graphical-session.target"];
      Wants = ["network-online.target"];
      PartOf = ["graphical-session.target"];
    };
    Install = {
      WantedBy = ["graphical-session.target"];
    };
    Service = {
      Type = "simple";
      WorkingDirectory = repoDir;
      Environment = [
        "COLLECTOR_BIN=${repoDir}/target/release/lifelog-collector"
        "SERVER_ADDR=http://100.118.206.104:7182"
        "LIFELOG_CONFIG_PATH=${home}/.config/lifelog/lifelog-config.toml"
        "LIFELOG_ALLOW_PLAINTEXT=1"
        "LIFELOG_COLLECTOR_ID=matts-laptop"
        "RUST_LOG=info"
        "XDG_RUNTIME_DIR=/run/user/%U"
      ];
      EnvironmentFile = authTokenEnv;
      PassEnvironment = "DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_SESSION_TYPE XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS";
      ExecStart = "${repoDir}/scripts/run_collector_service.sh";
      Restart = "always";
      RestartSec = 5;
    };
  };

  # Clean up the historical hand-placed unit file so Home Manager can manage
  # the symlink at ~/.config/systemd/user/lifelog-collector.service.
  home.activation.lifelogCollectorCleanup = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    if [ -e "$HOME/.config/systemd/user/lifelog-collector.service" ] \
       && [ ! -L "$HOME/.config/systemd/user/lifelog-collector.service" ]; then
      rm -f "$HOME/.config/systemd/user/lifelog-collector.service"
    fi
  '';
}
