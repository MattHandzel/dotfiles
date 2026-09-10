{
  config,
  host,
  lib,
  pkgs,
  ...
}: let
  # Platform test from the `host` specialArg, not from `pkgs` — see the
  # comment at the top of lib/scheduled.nix for why.
  isDarwin = host == "mac";
  isLinux = !isDarwin;
  # The prediction tracker itself lives in the vault (synced across machines);
  # this module only supplies the durable runner for its resolve frontend.
  script = "${config.home.homeDirectory}/Obsidian/Main/scripts/predictions/predict-ui";
  port = 7337;

  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  config = lib.mkMerge [
    (scheduled {
      name = "predict-ui";
      description = "prediction tracker resolve UI (http://127.0.0.1:${toString port})";
      command = ["${pkgs.python3}/bin/python3" script "--port" (toString port)];

      # Long-running, not a timer job.
      oneshot = false;
      restart = "on-failure";
      restartSec = 5;
      install.WantedBy = ["default.target"];

      # the vault is on /home; nothing else to wait for — binds localhost only
      unitExtra.ConditionPathExists = script;

      path = [pkgs.python3 pkgs.coreutils];
      logFile = "%h/.local/state/predict-ui.log";
      # launchd has no ConditionPathExists. KeepAlive.PathState makes the agent
      # run only while the vault script actually exists, which is the same
      # guard: a vault that has not synced yet does not produce a crash loop.
      launchdExtra.KeepAlive = {
        SuccessfulExit = false;
        PathState.${script} = true;
      };
    })
    # Vicinae (Mod+D) launch surface — see the CLAUDE.md rule: every user-facing
    # feature gets a desktop entry. Desktop entries are an XDG concept; on macOS
    # the same two commands are reached from Raycast.
    (lib.optionalAttrs isLinux {
      xdg.desktopEntries.predict-popup = {
        name = "Predict";
        genericName = "Prediction Tracker";
        comment = "Quick prediction capture popup (same as Super+P)";
        exec = "${config.home.homeDirectory}/Obsidian/Main/scripts/predictions/predict-popup";
        icon = "appointment-soon";
        type = "Application";
        categories = ["Utility"];
      };
      xdg.desktopEntries.predict-resolve = {
        name = "Predictions: Resolve";
        genericName = "Prediction Tracker";
        comment = "Open the prediction resolve UI (localhost:${toString port})";
        exec = "${pkgs.xdg-utils}/bin/xdg-open http://127.0.0.1:${toString port}";
        icon = "checkbox-checked-symbolic";
        type = "Application";
        categories = ["Utility"];
      };
    })
  ];
}
