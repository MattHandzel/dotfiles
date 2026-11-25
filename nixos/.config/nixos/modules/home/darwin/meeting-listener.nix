# meeting-listener: every minute, find each Wispr Flow meeting that has ended and whose refined
# transcript is done, check with a Haiku call that it's a real meeting Matt took part in, and start a
# background Opus session (one at a time) that runs the process-meeting skill on it. Results land in an
# actions file and a "Meetings processed by Claude" block in that day's daily note. Matt, 2026-10-08:
# "every single time I have a meeting that ends after the Wispr Flow transcript is done, it automatically
# runs Claude to process that meeting using the process-meeting skill."
#
# A poll, not a WatchPaths: Wispr's 1 GB flow.sqlite and its WAL change on every dictation, and readiness
# is a set of DB flags (finalized, transcriptReady, refineStatus) plus a settle time, not a file event.
# The script is referenced by its vault path, so edits take effect on the next tick without a rebuild.
# Code: ~/Obsidian/Main/scripts/meetings/meeting-listener. Doc: areas/second-brain/meeting-listener.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
in {
  # Every 10 min: write queued Beeper follow-ups into their chats' drafts, no focus change.
  # Never sends, never opens Beeper, never touches Swapcard (Matt, 2026-10-22).
  launchd.agents.stage-meeting-drafts = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${home}/Obsidian/Main/scripts/meetings/stage-drafts" "--auto"];
      StartInterval = 600;
      RunAtLoad = false;
      Nice = 5;
      EnvironmentVariables.PATH = "/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${home}/.local/state/meetings/stage-drafts.log";
      StandardErrorPath = "${home}/.local/state/meetings/stage-drafts.log";
    };
  };
  # Every 30 min: pull new actions files into the action-item ledger (areas/action-items/), read Matt's
  # ticks, and done-check open items through `lifelog check` (each at most every 6 h). Matt, 2026-10-29:
  # "you should be able to know what action items are complete or not ... in the Obsidian vault."
  launchd.agents.action-items-sync = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${home}/Obsidian/Main/scripts/meetings/actions" "sync"];
      StartInterval = 1800;
      RunAtLoad = false;
      Nice = 5;
      # claude (~/.local/bin) for the extract and judge calls, plus uv/rg for lifelog.
      EnvironmentVariables.PATH = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${home}/.local/state/action-items/launchd.log";
      StandardErrorPath = "${home}/.local/state/action-items/launchd.log";
    };
  };
  launchd.agents.meeting-listener = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${home}/Obsidian/Main/scripts/meetings/meeting-listener" "run"];
      # Runs the moment Wispr writes its database (a refine finishing is a write), at most every
      # 10 s; the 60 s interval is the fallback. An idle pass takes ~0.5 s. Matt, 2026-11-04:
      # "i want immediacy".
      WatchPaths = ["${home}/Library/Application Support/Wispr Flow/flow.sqlite" "${home}/Library/Application Support/Wispr Flow/flow.sqlite-wal"];
      ThrottleInterval = 10;
      StartInterval = 60;
      RunAtLoad = true;
      # Not Background/Nice: the `claude --bg` this runs can start Claude Code's shared daemon, which
      # keeps this job's clamp and passes it to every session in `claude agents` (PRI 4, the 2 E-cores
      # only). On 2026-10-19 that left forked sessions on "Waiting for session to redraw" for minutes.
      ProcessType = "Standard";
      # claude (~/.local/bin), plus the profiles for rg/fd/uv the session's tools call.
      EnvironmentVariables.PATH = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${home}/.local/state/meeting-listener/launchd.log";
      StandardErrorPath = "${home}/.local/state/meeting-listener/launchd.log";
    };
  };
}
