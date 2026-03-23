{pkgs, ...}: let
  python = pkgs.python3;
  curl = pkgs.curl;

  schedulerScript = pkgs.writeScript "ntfy-scheduler" ''
#!${python}/bin/python3
"""
ntfy notification scheduler.
Reads a JSON schedule file and sends notifications that are due.
Designed to run every minute via a systemd timer.

Schedule file: /home/matth/Obsidian/Main/agent/ntfy-schedule.json
State file: /home/matth/.local/state/ntfy-scheduler/state.json
"""

import json
import subprocess
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

SCHEDULE_FILE = Path("/home/matth/Obsidian/Main/agent/ntfy-schedule.json")
STATE_FILE = Path("/home/matth/.local/state/ntfy-scheduler/state.json")
NTFY_URL = "http://localhost:8124"
CURL = "${curl}/bin/curl"

def field_matches(pattern, value):
    """Check if a cron field pattern matches a value."""
    if pattern == "*":
        return True
    for part in pattern.split(","):
        if "/" in part:
            base, step = part.split("/", 1)
            step = int(step)
            if base == "*":
                if value % step == 0:
                    return True
            else:
                start = int(base.split("-")[0]) if "-" in base else int(base)
                if value >= start and (value - start) % step == 0:
                    return True
        elif "-" in part:
            lo, hi = part.split("-", 1)
            if int(lo) <= value <= int(hi):
                return True
        else:
            if int(part) == value:
                return True
    return False

def matches_cron(cron_expr, now):
    """Check if a 5-field cron expression matches the current time.
    Fields: minute hour day-of-month month day-of-week
    Day-of-week: 0=Sunday, 1=Monday, ..., 6=Saturday (standard cron)
    """
    fields = cron_expr.strip().split()
    if len(fields) != 5:
        return False
    cron_dow = (now.weekday() + 1) % 7
    checks = [
        (fields[0], now.minute),
        (fields[1], now.hour),
        (fields[2], now.day),
        (fields[3], now.month),
        (fields[4], cron_dow),
    ]
    return all(field_matches(p, v) for p, v in checks)

def load_state():
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {"sent_oneoffs": [], "last_run": None}

def save_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    state["last_run"] = datetime.now().isoformat()
    STATE_FILE.write_text(json.dumps(state, indent=2))

def send_notification(entry):
    topic = entry.get("topic", "claude")
    cmd = [CURL, "-s"]
    if entry.get("title"):
        cmd += ["-H", f"Title: {entry['title']}"]
    if entry.get("priority"):
        cmd += ["-H", f"Priority: {entry['priority']}"]
    if entry.get("tags"):
        cmd += ["-H", f"Tags: {entry['tags']}"]
    if entry.get("actions"):
        cmd += ["-H", f"Actions: {entry['actions']}"]
    cmd += ["-d", entry["message"], f"{NTFY_URL}/{topic}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Failed to send '{entry.get('id', '?')}': {result.stderr}", file=sys.stderr)
    else:
        print(f"Sent: {entry.get('id', '?')}")

def main():
    if not SCHEDULE_FILE.exists():
        print(f"Schedule file not found: {SCHEDULE_FILE}", file=sys.stderr)
        sys.exit(0)

    schedule = json.loads(SCHEDULE_FILE.read_text())
    state = load_state()
    now = datetime.now()

    for entry in schedule.get("recurring", []):
        if not entry.get("enabled", True):
            continue
        if matches_cron(entry["cron"], now):
            send_notification(entry)

    for entry in schedule.get("oneoff", []):
        if not entry.get("enabled", True):
            continue
        if entry["id"] in state["sent_oneoffs"]:
            continue
        send_at = datetime.fromisoformat(entry["send_at"])
        if now >= send_at:
            send_notification(entry)
            state["sent_oneoffs"].append(entry["id"])

    save_state(state)

if __name__ == "__main__":
    main()
  '';
in {
  systemd.services.ntfy-scheduler = {
    description = "ntfy notification scheduler - sends due notifications from schedule file";
    after = ["network.target" "ntfy-sh.service"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${schedulerScript}";
    };
  };

  systemd.timers.ntfy-scheduler = {
    description = "Run ntfy scheduler every minute";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* *:*:00";
      Persistent = true;
    };
  };
}
