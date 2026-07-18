{pkgs, ...}: let
  python = pkgs.python3;
  curl = pkgs.curl;

  watcherScript = pkgs.writeScript "project-watcher" ''
    #!${pkgs.bash}/bin/bash
    export PATH="${python}/bin:${curl}/bin:$PATH"
    exec ${python}/bin/python3 /home/matth/Obsidian/Main/scripts/project-watcher.py
  '';
in {
  systemd.services.project-watcher = {
    description = "Scan Obsidian vault projects for staleness and missing worklogs";
    after = ["network.target" "ntfy-sh.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${watcherScript}";
    };
  };

  systemd.timers.project-watcher = {
    description = "Run project watcher daily at 09:00 CT";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 09:00:00";
      Persistent = true;
    };
  };
}
