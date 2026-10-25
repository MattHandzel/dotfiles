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
    from zoneinfo import ZoneInfo

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

    # A one-off more than this late is recorded as sent without sending, so an
    # outage (the server was off Jul-Oct 2026) never ends in a burst of stale
    # reminders.
    ONEOFF_GRACE_SECONDS = 6 * 3600

    def parse_send_at(entry, tz):
        send_at = datetime.fromisoformat(entry["send_at"])
        if send_at.tzinfo is None:
            send_at = send_at.replace(tzinfo=tz)
        return send_at

    def load_state(schedule, tz, now):
        """Read the state file. A missing, empty or corrupt file is rebuilt
        rather than crashing every run: every one-off already due counts as
        sent. (2026-07-23: a power cut left a 0-byte state.json and the unit
        failed every minute for three months.)"""
        try:
            state = json.loads(STATE_FILE.read_text())
            state.setdefault("sent_oneoffs", [])
            return state
        except FileNotFoundError:
            reason = "missing"
        except (json.JSONDecodeError, OSError, AttributeError) as exc:
            reason = f"unreadable ({exc.__class__.__name__})"
        due = []
        for entry in schedule.get("oneoff", []):
            try:
                if parse_send_at(entry, tz) <= now:
                    due.append(entry["id"])
            except (KeyError, ValueError):
                continue
        print(f"State file {reason}; rebuilt with {len(due)} past one-offs marked sent", file=sys.stderr)
        return {"sent_oneoffs": due, "last_run": None}

    def save_state(state):
        """Write to a temp file, fsync, then rename, so a crash or power cut
        leaves the old state or the new one, never a truncated file."""
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        state["last_run"] = datetime.now().isoformat()
        tmp = STATE_FILE.with_name(STATE_FILE.name + ".tmp")
        with open(tmp, "w") as fh:
            fh.write(json.dumps(state, indent=2))
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, STATE_FILE)

    def send_notification(entry):
        topic = entry.get("topic", "claude")
        cmd = [CURL, "-s", "--fail", "--max-time", "20"]
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
            print(f"Failed to send '{entry.get('id', '?')}': curl exit {result.returncode} {result.stderr}", file=sys.stderr)
            return False
        print(f"Sent: {entry.get('id', '?')}")
        return True

    def main():
        if not SCHEDULE_FILE.exists():
            print(f"Schedule file not found: {SCHEDULE_FILE}", file=sys.stderr)
            sys.exit(0)

        try:
            schedule = json.loads(SCHEDULE_FILE.read_text())
        except json.JSONDecodeError as exc:
            # Fail loudly: a broken schedule means no reminders at all.
            print(f"Schedule file is not valid JSON: {exc}", file=sys.stderr)
            sys.exit(1)
        tz_name = schedule.get("_timezone", "America/Los_Angeles")
        try:
            tz = ZoneInfo(tz_name)
        except Exception:
            print(f"Warning: invalid timezone '{tz_name}', using America/Los_Angeles", file=sys.stderr)
            tz = ZoneInfo("America/Los_Angeles")
        now = datetime.now(tz)
        state = load_state(schedule, tz, now)
        failed = False

        # One bad entry must not stop the others.
        for entry in schedule.get("recurring", []):
            if not entry.get("enabled", True):
                continue
            try:
                due = matches_cron(entry["cron"], now)
            except (KeyError, ValueError) as exc:
                print(f"Bad recurring entry '{entry.get('id', '?')}': {exc}", file=sys.stderr)
                failed = True
                continue
            if due and not send_notification(entry):
                failed = True

        for entry in schedule.get("oneoff", []):
            if not entry.get("enabled", True) or entry.get("id") in state["sent_oneoffs"]:
                continue
            try:
                send_at = parse_send_at(entry, tz)
            except (KeyError, ValueError) as exc:
                print(f"Bad one-off entry '{entry.get('id', '?')}': {exc}", file=sys.stderr)
                failed = True
                continue
            if now < send_at:
                continue
            if (now - send_at).total_seconds() > ONEOFF_GRACE_SECONDS:
                print(f"Skipped stale one-off: {entry['id']} (due {entry['send_at']})")
                state["sent_oneoffs"].append(entry["id"])
            elif send_notification(entry):
                state["sent_oneoffs"].append(entry["id"])
            else:
                failed = True

        save_state(state)
        sys.exit(1 if failed else 0)

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
