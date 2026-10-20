# Daily finance audit: SimpleFIN -> SQLite ledger -> status note, dashboard, audits, alerts.
#
# `fin daily` is idempotent: it syncs at most once a day (SimpleFIN allows ~24 requests/day),
# rebuilds areas/finance/status.md + dashboard/index.html, writes the weekly audit (Sundays, or
# whenever the last one is >7 days old) and the monthly close (once per month), and posts a
# macOS notification for each NEW high/medium finding. Exit 2 = data is stale (health is
# freshness, not exit status — the Firefly outage lesson).
#
# Code: ~/Obsidian/Main/scripts/finance (stdlib-only Python). Doc: areas/second-brain/finance-pipeline.md
{pkgs, ...}: let
  fin = "/Users/matth/Obsidian/Main/scripts/finance/fin";
  run = pkgs.writeShellApplication {
    name = "finance-daily-run";
    runtimeInputs = [pkgs.python3];
    text = ''
      echo "== $(date -u +%FT%TZ) finance daily"
      rc=0
      python3 "${fin}" daily || rc=$?
      if [ "$rc" -eq 1 ]; then
        /usr/bin/osascript -e 'display notification "fin daily crashed - see ~/Library/Logs/finance-daily.log" with title "Finance"' || true
      fi
      exit 0
    '';
  };
in {
  launchd.agents.finance-daily = {
    enable = true;
    config = {
      ProgramArguments = ["${run}/bin/finance-daily-run"];
      # 07:15 daily; launchd fires a missed calendar job when the Mac next wakes.
      StartCalendarInterval = [
        {
          Hour = 7;
          Minute = 15;
        }
      ];
      ProcessType = "Background";
      Nice = 10;
      StandardOutPath = "/Users/matth/Library/Logs/finance-daily.log";
      StandardErrorPath = "/Users/matth/Library/Logs/finance-daily.log";
    };
  };
}
