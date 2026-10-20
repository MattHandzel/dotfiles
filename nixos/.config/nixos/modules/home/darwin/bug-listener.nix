# bug-listener: every 2 minutes, and whenever a capture lands, file each capture tagged bug / feature /
# annoyance on the bug board (~/Obsidian/Main/areas/bugs/bug-board.md), sort it with Sonnet, and start a
# background Claude session (one at a time, capped per day) to fix bugs in software Matt owns. Features
# and life bugs wait for his yes on the board. Matt, 2026-10-07: "something that consistently checks for
# it ... so that I don't need to just send you messages in this chat, and then you can work on those
# problems autonomously."
#
# The script is referenced by its vault path, so edits take effect on the next tick without a rebuild.
# launchd never starts a second copy while one is still running, and the script also takes a lock.
# Code: ~/Obsidian/Main/scripts/bugs/bug-listener. Doc: areas/second-brain/bug-listener.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
in {
  launchd.agents.bug-listener = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${home}/Obsidian/Main/scripts/bugs/bug-listener" "run"];
      StartInterval = 120;
      WatchPaths = ["${home}/Obsidian/Main/capture/raw_capture"];
      RunAtLoad = true;
      # Standard, not Background/Nice: a `claude --bg` started from here can spawn Claude Code's shared
      # daemon, and every agents-view session would inherit the clamp (see meeting-listener.nix).
      ProcessType = "Standard";
      # claude (~/.local/bin), uv for bug-context's Beeper lookup, git and rg from the profiles.
      EnvironmentVariables.PATH = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${home}/.local/state/bug-listener/launchd.log";
      StandardErrorPath = "${home}/.local/state/bug-listener/launchd.log";
    };
  };
}
