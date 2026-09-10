{pkgs, ...}: {
  # Google Drive mounted at ~/gdrive via rclone (remote "gdrive" in
  # ~/.config/rclone/rclone.conf — created once, interactively, with
  # `rclone config create gdrive drive scope=drive`; the OAuth token lives in
  # that file and rclone refreshes it itself). Session-independent, so bind to
  # default.target like aw-server.
  systemd.user.services.gdrive-mount = {
    Unit = {
      Description = "Google Drive rclone mount at ~/gdrive";
      # Don't flap forever if the network is down or the token is revoked.
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      # --vfs-cache-mode writes: files open read-write locally, uploads happen
      # on close — without it many apps (editors doing atomic saves) break.
      ExecStart = "${pkgs.rclone}/bin/rclone mount gdrive: %h/gdrive --vfs-cache-mode writes";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p %h/gdrive";
      # fusermount lives in the FUSE package; unmount cleanly on stop.
      ExecStop = "${pkgs.fuse}/bin/fusermount -u %h/gdrive";
      Restart = "on-failure";
      RestartSec = 15;
    };
    Install.WantedBy = ["default.target"];
  };
}
