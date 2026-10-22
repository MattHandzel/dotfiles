# lifelog-store: keep the lifelog store (~/.local/share/lifelog/lifelog.db) filled and inside its limits.
#
#   lifelog-ingest   every 5 min, the main lane: ActivityWatch, Dayflow cards and observations, Dia, atuin,
#                    Claude prompts, the calendar, commits, saved files, the Work Test clock, Oops, phone
#                    pickups, places, Mac sleep/wake, macOS notifications, Taskwarrior, Drive shares. Most
#                    overdue first; a source skipped for time is logged and shows in `lifelog stats` (BEHIND).
#   lifelog-ingest-messages  every 2 min, the messaging lane: every Beeper message (all networks, both
#                    directions), every Gmail message, the inbox/ drop folder (Swapcard, LinkedIn web exports),
#                    Wispr meetings, shares and dictations, Google Calendar invites, captures.
#                    Each source keeps its own cursor and minimum interval; each lane holds its own lock, so a
#                    slow pass is never doubled and can't hold the other lane back.
#   lifelog-archive  03:40 nightly: whole months older than policy.toml's hot_days move into zstd archives,
#                    old Dayflow chunks are re-encoded (only once policy.toml says reencode = true), old frame
#                    caches go, and every limit is checked (a Mac notification when one is passed).
#
# Matt, 2026-10-07: "ensure this system gets all messages and emails from beeper and the email ... make it
# highly performant for querying, taking up not that much space, the ability to archive automatically to save
# storage, storage limits". The scripts are referenced by their vault paths, so edits apply on the next run
# without a rebuild. Code: ~/Obsidian/Main/scripts/lifelog/{ingest,store,storage}.py. Doc: areas/second-brain/lifelog.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  lifelog = "${home}/Obsidian/Main/scripts/lifelog/lifelog.py";
  # fd (files), git (commits), task (Taskwarrior), icalBuddy (calendar), ffmpeg/ffprobe (Dayflow archive)
  path = "/etc/profiles/per-user/${config.home.username}/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin:/opt/homebrew/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
  log = "${home}/.local/state/lifelog/store.log";
  # None of these is ProcessType "Background" or LowPriorityIO (2026-10-20). Under memory pressure macOS starved
  # them: a main pass ran 30+ min against its 200 s budget and the store went 13 hours without most sources
  # (every source behind the slow one was skipped, pass after pass). Measured that morning: importing the
  # ingester and one query took 1.2 s at normal priority and 56.6 s clamped to background (`taskpolicy -b`).
  # Nice still keeps them polite on CPU; ingest.py stops any one source at a hard limit.
in {
  launchd.agents.lifelog-ingest = {
    enable = true;
    config = {
      # --lane main: the messaging lane has its own agent below, so this pass spends its whole budget on the rest.
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" lifelog "ingest" "--lane" "main" "--budget" "200" "--quiet"];
      StartInterval = 300;
      RunAtLoad = true;
      Nice = 10;
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
  # The messaging lane alone (Beeper, Gmail, the inbox/ drop folder, Wispr meetings and dictations, Google
  # Calendar invites, captures), under its own lock, so a slow main pass can't hold messages back. On 2026-10-19,
  # under load, one main pass ran 30+ min (Dayflow 626 s, git 806 s) and launchd doesn't start a job that's
  # still running, so Beeper went hours without a pass and done-checks missed messages Matt had sent.
  launchd.agents.lifelog-ingest-messages = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" lifelog "ingest" "--lane" "messages" "--budget" "90" "--quiet"];
      StartInterval = 120;
      RunAtLoad = true;
      Nice = 5;
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
  launchd.agents.lifelog-archive = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" lifelog "archive" "--apply" "--quiet"];
      StartCalendarInterval = [
        {
          Hour = 3;
          Minute = 40;
        }
      ];
      # Also holds the main lane's lock while it moves old months out, so a throttled run blocked ingest too.
      Nice = 15;
      EnvironmentVariables.PATH = path;
      StandardOutPath = log;
      StandardErrorPath = log;
    };
  };
}
