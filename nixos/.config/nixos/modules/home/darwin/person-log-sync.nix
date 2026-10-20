# Daily people sync: every meeting, email, DM chat, call and calendar event lands in the person's
# file under ~/Obsidian/Main/areas/relationships/ (and the full archive in relationship-data/<slug>/).
# Idempotent, no LLM calls; mentions it can't pin down go to _identity-review.md (Raycast "Who Is This").
# Code: ~/Obsidian/Main/scripts/relationships/person_log.py. Doc: areas/second-brain/person-resolver.md
_: {
  launchd.agents.person-log-sync = {
    enable = true;
    config = {
      ProgramArguments = ["/bin/bash" "/Users/matth/Obsidian/Main/scripts/relationships/person-log-sync.sh"];
      # 06:40 daily (after lifelog-ingest has caught up overnight); a missed run fires on wake.
      StartCalendarInterval = [
        {
          Hour = 6;
          Minute = 40;
        }
      ];
      ProcessType = "Background";
      Nice = 10;
      StandardOutPath = "/Users/matth/Library/Logs/person-log-sync.log";
      StandardErrorPath = "/Users/matth/Library/Logs/person-log-sync.log";
    };
  };
}
