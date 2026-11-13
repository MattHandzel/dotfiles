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
  scriptsDir = "${config.home.homeDirectory}/Projects/gmail-automation";
  stateDir = "${config.home.homeDirectory}/.local/state/gmail-automation";

  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;
in {
  # email-do: the Gmail label queue (`claude/do`, or a forward to
  # handzelmatthew+claude@gmail.com) that hands one thread at a time to a
  # headless Claude worker on this machine. The poller is stdlib Python over
  # Gmail IMAP (app password at ~/.config/gmail-automation/app-password); the
  # worker is `claude -p` with the email-do-it skill. Every report is a Gmail
  # draft; nothing is ever sent. See ~/Projects/gmail-automation/README.md.
  config = lib.mkMerge [
    (lib.optionalAttrs isDarwin {
      home.file.".local/state/gmail-automation/claude-do/.keep".text = "";
    })
    (scheduled {
      name = "email-do-poll";
      description = "email-do: poll the claude/do Gmail queue and spawn workers (every 3min)";
      # One pass is 3-35 s. launchd never starts the next tick while a pass is
      # alive, so a pass that never returns freezes the queue with exit 0 and
      # only a stale log: 14 h on 2026-11-11 (a dead IMAP socket, since fixed
      # with a socket timeout) and 13:36-14:37 on 2026-11-13 (the Mac
      # thrashing: load ~146, 11 GB swap; err-email-do-poll-20261113-143143).
      # So every pass gets a wall-clock limit: TERM at 10 min, KILL 15 s
      # later, exit 124/137 so the error collector sees it. Workers run in
      # their own session (start_new_session) and are not touched.
      command = ["${pkgs.coreutils}/bin/timeout" "-k" "15" "600" "${pkgs.python3}/bin/python3" "${scriptsDir}/claude_do.py" "poll"];
      onCalendar = "*:0/3";
      persistent = false;
      everySeconds = 180;
      workingDirectory = config.home.homeDirectory;
      # The worker shells out to `claude`, plus jq and coreutils' `timeout`. A
      # LaunchAgent starts with no PATH at all. Claude Code's native installer
      # lives in ~/.local/bin (the Homebrew copy is gone), so that goes first,
      # as in zsh.nix; without it every worker died with rc=127 (bug
      # 2026-10-26T20:06:21.800Z).
      path = [pkgs.bash pkgs.coreutils pkgs.python3 pkgs.jq pkgs.git pkgs.curl];
      darwinPathEntries = [
        "${config.home.homeDirectory}/.local/bin"
        "/opt/homebrew/bin"
        "${config.home.homeDirectory}/.nix-profile/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ];
      linuxPathEntries = [
        "/run/current-system/sw/bin"
        "${config.home.homeDirectory}/.nix-profile/bin"
        "/etc/profiles/per-user/matth/bin"
      ];
      environment = {HOME = config.home.homeDirectory;};
      logFile = "${stateDir}/claude-do-poll.log";
      linuxLogFile = "${stateDir}/claude-do-poll.log";
      timerUnit = "email-do-poll.service";
    })
  ];
}
