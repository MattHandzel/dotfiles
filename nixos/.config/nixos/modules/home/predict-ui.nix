{pkgs, ...}: let
  # The prediction tracker itself lives in the vault (synced across machines);
  # this module only supplies the durable runner for its resolve frontend.
  script = "/home/matth/Obsidian/Main/scripts/predictions/predict-ui";
  port = 7337;
in {
  systemd.user.services.predict-ui = {
    Unit = {
      Description = "prediction tracker resolve UI (http://127.0.0.1:7337)";
      # the vault is on /home; nothing else to wait for — binds localhost only
      ConditionPathExists = script;
    };
    Service = {
      ExecStart = "${pkgs.python3}/bin/python3 ${script} --port ${toString port}";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["default.target"];
  };

  # Vicinae (Mod+D) launch surface — see the CLAUDE.md rule: every user-facing
  # feature gets a desktop entry
  xdg.desktopEntries.predict-popup = {
    name = "Predict";
    genericName = "Prediction Tracker";
    comment = "Quick prediction capture popup (same as Super+P)";
    exec = "/home/matth/Obsidian/Main/scripts/predictions/predict-popup";
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
}
