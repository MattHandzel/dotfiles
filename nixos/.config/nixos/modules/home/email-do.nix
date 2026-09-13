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
      command = ["${pkgs.python3}/bin/python3" "${scriptsDir}/claude_do.py" "poll"];
      onCalendar = "*:0/3";
      persistent = false;
      everySeconds = 180;
      workingDirectory = config.home.homeDirectory;
      # The worker shells out to `claude` (Homebrew) which needs node, plus jq
      # and coreutils' `timeout`. A LaunchAgent starts with no PATH at all.
      path = [pkgs.bash pkgs.coreutils pkgs.python3 pkgs.jq pkgs.git pkgs.curl];
      darwinPathEntries = [
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
