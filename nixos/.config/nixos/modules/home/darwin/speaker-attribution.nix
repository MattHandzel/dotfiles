# speaker-attribution: who said what in each recorded meeting, and the rolling model of Matt it needs.
#
# Two agents, both calling scripts by their vault path so edits take effect without a rebuild:
#
#   matt-self-model      daily 05:40: scripts/meetings/self_model.py build. Rebuilds
#                        agent/state/matt-self-model.{json,md} (who Matt is right now: role, programs, projects,
#                        background, recent events) from his daily notes, calendar, projects, his own words in
#                        Wispr-resolved meetings and his self-descriptions. Facts are dated and decay, so a new
#                        job shows up and an old role drops out with no hand edits. ~$0.05-0.15 a day (Haiku per
#                        new document, cached; one Sonnet merge).
#   speaker-attribution  every 15 min: scripts/meetings/speakers.py run --days 14. Labels each turn of any new or
#                        changed unresolved transcript (Wispr, Plaud, pasted) as Matt / a named person / unclear,
#                        into capture/meetings/transcripts/speakers/<stem>.json plus line-neutral annotations in
#                        the note. Fresh Wispr meetings are usually done already: meeting-listener runs speakers.py
#                        on each one before process-meeting starts. No-op when nothing changed.
#
# A poll, not WatchPaths: the transcripts folder changes on every 15-min Wispr re-render and on our own annotation
# writes, so a watch would mostly wake to no-ops. Doc: ~/Obsidian/Main/areas/second-brain/speaker-attribution.md
{
  config,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  scripts = "${home}/Obsidian/Main/scripts/meetings";
  logDir = "${home}/.local/state/speaker-attribution";
  # claude (~/.local/bin) for the model calls, icalBuddy (/opt/homebrew/bin) for who.py's calendar lookup.
  path = "${home}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
in {
  launchd.agents.matt-self-model = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${scripts}/self_model.py" "build"];
      StartCalendarInterval = [{Hour = 5; Minute = 40;}];
      RunAtLoad = false;
      # Standard, not Background: under Background macOS throttles CPU/IO so hard that on a loaded Mac (load
      # 100-200) each `claude -p` takes minutes and hits self_model.py's timeouts (bug
      # err-matt-self-model-20261115-101631; 3 s -> 90 s at load 30). The job mostly waits on the network.
      ProcessType = "Standard";
      EnvironmentVariables.PATH = path;
      StandardOutPath = "${logDir}/self-model.log";
      StandardErrorPath = "${logDir}/self-model.log";
    };
  };
  launchd.agents.speaker-attribution = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${scripts}/speakers.py" "run" "--days" "14" "--jobs" "2"];
      StartInterval = 900;
      RunAtLoad = false;
      ProcessType = "Background";
      EnvironmentVariables.PATH = path;
      StandardOutPath = "${logDir}/attribution.log";
      StandardErrorPath = "${logDir}/attribution.log";
    };
  };
}
