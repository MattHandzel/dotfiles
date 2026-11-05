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
  home = config.home.homeDirectory;
  vault = "${home}/Obsidian/Main";
  dlg = "${vault}/scripts/delegate/delegate";
  stateDir = "${home}/.local/state/delegate";
  python = "${pkgs.python3}/bin/python3";

  inherit (import ./lib/scheduled.nix {inherit lib pkgs config isDarwin;}) scheduled;

  # Workers shell out to `claude` (native install in ~/.local/bin on the Mac, the
  # system profile on the server), the poll to `ssh` for the other machine.
  darwinPath = [
    "${home}/.local/bin"
    "/opt/homebrew/bin"
    "${home}/.nix-profile/bin"
    "/etc/profiles/per-user/matth/bin"
    "/run/current-system/sw/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
  linuxPath = [
    "/run/current-system/sw/bin"
    "${home}/.nix-profile/bin"
    "/etc/profiles/per-user/matth/bin"
  ];
in {
  # delegate: one engine for every way Matt hands Claude a whole task (the
  # Delegate hotkey/UI and Raycast command on the Mac, the `delegate` CLI, the
  # Gmail claude/do label, Triage's "Do this", an issue written into the Linear
  # project "Delegate"). Per-host SQLite queue in ~/.local/state/delegate, Linear
  # as the shared record, workers are `claude -p` with the delegate-do-it skill.
  # Code: ~/Obsidian/Main/scripts/delegate (syncs to the server with the vault).
  # Doc: ~/Obsidian/Main/areas/second-brain/delegate.md
  config = lib.mkMerge [
    # Every minute, on both machines: start queued tasks when a slot is free,
    # retry hand-offs to the other machine, mirror handed tasks, file the Linear
    # cards that were deferred (free cap, offline), claim issues Matt wrote into
    # the project by hand, and notice canceled cards.
    (scheduled {
      name = "delegate-poll";
      description = "delegate: start queued tasks, mirror the other machine, sync Linear (every minute)";
      command = [python dlg "poll"];
      onCalendar = "*:*:00";
      persistent = false;
      everySeconds = 60;
      workingDirectory = vault;
      path = [pkgs.bash pkgs.coreutils pkgs.python3 pkgs.openssh pkgs.git pkgs.curl];
      darwinPathEntries = darwinPath;
      linuxPathEntries = linuxPath;
      environment = {HOME = home;};
      logFile = "${stateDir}/poll.log";
      linuxLogFile = "${stateDir}/poll.log";
      timerUnit = "delegate-poll.service";
    })
    # Mac only: the UI + API on 127.0.0.1:47470, always up so the hotkey opens
    # instantly (it also runs the poll every 20 s while it's alive).
    (lib.optionalAttrs isDarwin {
      home.file.".local/state/delegate/.keep".text = "";
      launchd.agents.delegate-serve = {
        enable = true;
        config = {
          ProgramArguments = [python dlg "serve"];
          RunAtLoad = true;
          KeepAlive = true;
          WorkingDirectory = vault;
          EnvironmentVariables = {
            HOME = home;
            PATH = lib.concatStringsSep ":" darwinPath;
          };
          StandardOutPath = "${stateDir}/serve.log";
          StandardErrorPath = "${stateDir}/serve.log";
        };
      };
    })
  ];
}
