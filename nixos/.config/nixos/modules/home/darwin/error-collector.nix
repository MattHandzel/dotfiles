# error-collector: every 5 minutes, gather every error on the Mac into one store: his launchd agents that
# exited non-zero, ERROR lines and tracebacks in ~/.local/state logs, crash reports, the Hammerspoon console,
# and anything a script files with `error-collector report`. Every 3 hours (09:00-22:00) the new ones go to
# the bug listener as one batch, one item per app, each waiting for Matt's yes on the bug board before a
# Claude fix session starts. Matt, Oops 20261019-174402: "ALL errors that happen EVERYWHERE to be
# automatically logged, triaged, and also somewhat automatically fixed ... for now, just ask for my approval
# & batch errors". lifelog reads the same store (`lifelog span … --only errors`).
#
# The script is referenced by its vault path, so edits take effect on the next tick without a rebuild.
# Code: ~/Obsidian/Main/scripts/bugs/error-collector. Doc: areas/second-brain/error-collector.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  script = "${home}/Obsidian/Main/scripts/bugs/error-collector";
in {
  # On PATH for scripts and apps: `error-collector report --source my-tool --message "…"` (always exits 0).
  home.packages = [
    (pkgs.writeShellScriptBin "error-collector" ''exec ${pkgs.python3}/bin/python3 -I ${script} "$@"'')
  ];

  launchd.agents.error-collector = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" script "scan"];
      StartInterval = 300;
      RunAtLoad = true;
      # Standard, like bug-listener.nix: after a batch it runs a listener pass, which can call `claude`.
      ProcessType = "Standard";
      EnvironmentVariables.PATH = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${home}/.local/state/error-collector/launchd.log";
      StandardErrorPath = "${home}/.local/state/error-collector/launchd.log";
    };
  };
}
