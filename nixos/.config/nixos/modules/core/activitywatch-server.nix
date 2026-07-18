{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.activitywatch-server;
in {
  options.services.activitywatch-server = {
    enable = lib.mkEnableOption "ActivityWatch server (aw-server-rust) for self-hosted time tracking";
    port = lib.mkOption {
      type = lib.types.port;
      default = 5600;
      description = "Port for aw-server to listen on.";
    };
    host = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Bind address. 0.0.0.0 lets the Pixel post events over Tailscale; firewall is restricted to Tailscale interface separately.";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "matth";
      description = "User to run aw-server as.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.aw-server = {
      description = "ActivityWatch server (Rust)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        ExecStart = "${pkgs.activitywatch}/bin/aw-server --host ${cfg.host} --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
