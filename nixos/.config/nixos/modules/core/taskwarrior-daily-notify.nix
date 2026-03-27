{pkgs, ...}: let
  python = pkgs.python3;
  curl = pkgs.curl;

  notifyScript = pkgs.writeScript "taskwarrior-daily-notify" ''
#!${python}/bin/python3
"""
Send ntfy notification with tasks due today/overdue.
Reads exported JSON from Syncthing (no Taskwarrior needed on server).
Runs daily at 10:00 CT (= 08:00 PT).
"""

import json
import subprocess
import sys
from datetime import datetime, date
from pathlib import Path

TASK_FILE = Path("/home/matth/Obsidian/Main/taskwarrior/pending-tasks.json")
EXPORT_TIME_FILE = Path("/home/matth/Obsidian/Main/taskwarrior/last-export.txt")
NTFY_URL = "http://localhost:8124/claude"
CURL = "${curl}/bin/curl"

def main():
    if not TASK_FILE.exists():
        print(f"No task export found at {TASK_FILE}", file=sys.stderr)
        return

    # Check freshness
    if EXPORT_TIME_FILE.exists():
        try:
            export_text = EXPORT_TIME_FILE.read_text().strip()
            from datetime import timezone
            import re
            # Parse ISO format
            export_dt = datetime.fromisoformat(export_text)
            age_hours = (datetime.now(export_dt.tzinfo or None) - export_dt).total_seconds() / 3600
            if age_hours > 12:
                subprocess.run([CURL, "-s",
                    "-H", "Title: Task export stale",
                    "-H", "Priority: low",
                    "-d", f"Task data is {int(age_hours)} hours old. Is your laptop syncing?",
                    NTFY_URL], capture_output=True)
                return
        except Exception:
            pass  # If we can't parse, proceed anyway

    today = date.today()

    with open(TASK_FILE) as f:
        tasks = json.load(f)

    overdue = []
    due_today = []

    for t in tasks:
        if "due" not in t or t.get("status") != "pending":
            continue
        due_str = t["due"][:8]
        try:
            due_date = datetime.strptime(due_str, "%Y%m%d").date()
        except ValueError:
            continue

        desc = t.get("description", "???")
        project = t.get("project", "")
        priority = t.get("priority", "")
        prefix = f"[{priority}] " if priority else ""
        proj = f" ({project})" if project else ""
        line = f"{prefix}{desc}{proj}"

        if due_date < today:
            overdue.append(line)
        elif due_date == today:
            due_today.append(line)

    total = len(overdue) + len(due_today)
    if total == 0:
        print("No tasks due today or overdue.")
        return

    msg_parts = []
    if overdue:
        msg_parts.append("OVERDUE:\n" + "\n".join(f"  - {t}" for t in overdue))
    if due_today:
        msg_parts.append("DUE TODAY:\n" + "\n".join(f"  - {t}" for t in due_today))

    msg = "\n\n".join(msg_parts)
    priority = "high" if overdue else "default"
    title = f"{total} tasks need attention"
    if overdue:
        title += f" ({len(overdue)} overdue)"

    result = subprocess.run([CURL, "-s",
        "-H", f"Title: {title}",
        "-H", f"Priority: {priority}",
        "-H", "Tags: clipboard",
        "-d", msg,
        NTFY_URL], capture_output=True, text=True)

    if result.returncode == 0:
        print(f"Sent notification: {title}")
    else:
        print(f"Failed: {result.stderr}", file=sys.stderr)

if __name__ == "__main__":
    main()
  '';
in {
  systemd.services.taskwarrior-daily-notify = {
    description = "Send ntfy notification with tasks due today/overdue";
    after = ["network.target" "ntfy-sh.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${notifyScript}";
    };
  };

  systemd.timers.taskwarrior-daily-notify = {
    description = "Send task notifications daily at 10:00 CT (08:00 PT)";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 10:00:00";
      Persistent = true;
    };
  };
}
