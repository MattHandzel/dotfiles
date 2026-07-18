{pkgs, ...}: let
  # Python bundled with the Google client libraries the poller needs.
  # No pip, no ~/.local — everything reproducible through Nix.
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    google-auth-oauthlib
    google-api-python-client
  ]);

  # The poller lives in ~/Projects/gmail-automation/ (canonical engine layout).
  pollerPath = "/home/matth/Projects/gmail-automation/poller.py";

  # Wrapper script: set PATH so `task` CLI is findable, then exec the poller
  # with the bundled Python interpreter.
  runPoller = pkgs.writeShellScript "gmail-automation-run" ''
    export PATH="${pkgs.taskwarrior3}/bin:${pkgs.coreutils}/bin:$PATH"
    exec ${pythonEnv}/bin/python3 ${pollerPath}
  '';
in {
  systemd.services.gmail-automation = {
    description = "Gmail label -> Taskwarrior + snooze poller";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      # HOME is needed so taskwarrior finds ~/.taskrc and the poller finds
      # ~/.config/gmail-automation/token.json.
      Environment = [
        "HOME=/home/matth"
      ];
      ExecStart = "${runPoller}";
      # Don't bomb the logs if a cycle fails — the next timer tick will retry.
      # Exit 0 on success, 1 on transient API error, 2 on missing token.
      SuccessExitStatus = "0 1 2";
    };
  };

  systemd.timers.gmail-automation = {
    description = "Run gmail-automation poller every 5 minutes";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      # Catch up on missed runs after laptop suspend/resume.
      Persistent = true;
      Unit = "gmail-automation.service";
    };
  };
}
