# Daily server health push: one ntfy message when something is wrong, nothing
# when it isn't, plus a Monday "all green" so silence can't be mistaken for
# health.
#
# Why (2026-10-25): the server came back from three months offline with 24
# failed units, a vault that had not synced since July, and an ntfy-scheduler
# that had crashed every minute since a power cut. None of it alerted, because
# the only alerts were from dead fleet units shouting about their own scripts.
# This replaces that noise with one message a day about the things that matter.
{pkgs, ...}: let
  digest = pkgs.writeScript "server-health-digest" ''
    #!${pkgs.python3}/bin/python3
    import json, re, shutil, subprocess, sys, urllib.request
    from datetime import datetime, timezone

    NTFY = "http://localhost:8124/claude"
    SYNCTHING = "http://127.0.0.1:8384"
    VAULT_FOLDER = "r9mpp-yvvmy"
    # Device -> hours of silence before it counts as a problem.
    DEVICE_LIMITS = {"matts-mac": 24, "Pixel 9a": 72}
    SCHEDULER_STATE = "/home/matth/.local/state/ntfy-scheduler/state.json"
    SYSTEMCTL = "${pkgs.systemd}/bin/systemctl"

    problems = []

    def failed_units(user):
        cmd = [SYSTEMCTL] + (["--user"] if user else []) + ["--failed", "--no-legend", "--plain"]
        out = subprocess.run(cmd, capture_output=True, text=True).stdout
        return [line.split()[0] for line in out.splitlines() if line.strip()]

    units = failed_units(False) + [f"user:{u}" for u in failed_units(True)]
    if units:
        problems.append(f"{len(units)} failed units: " + ", ".join(units[:12]) + (" ..." if len(units) > 12 else ""))

    try:
        cfg = open("/home/matth/.config/syncthing/config.xml").read()
        key = re.search(r"<apikey>([^<]+)</apikey>", cfg).group(1)
        def st(path):
            req = urllib.request.Request(SYNCTHING + path, headers={"X-API-Key": key})
            return json.load(urllib.request.urlopen(req, timeout=10))
        names = {d["deviceID"]: d["name"] for d in st("/rest/config/devices")}
        stats = st("/rest/stats/device")
        now = datetime.now(timezone.utc)
        for dev_id, name in names.items():
            limit = DEVICE_LIMITS.get(name)
            if limit is None or dev_id not in stats:
                continue
            seen = datetime.fromisoformat(stats[dev_id]["lastSeen"].replace("Z", "+00:00"))
            hours = (now - seen).total_seconds() / 3600
            if hours > limit:
                ago = "never" if seen.year < 2000 else f"{hours / 24:.1f} days ago"
                problems.append(f"Syncthing: {name} last connected {ago}; the vault is not syncing with it")
        status = st(f"/rest/db/status?folder={VAULT_FOLDER}")
        if status.get("errors") or status.get("pullErrors"):
            problems.append(f"Syncthing: vault folder has {status.get('pullErrors') or status.get('errors')} pull errors")
    except Exception as exc:
        problems.append(f"Syncthing check failed: {exc}")

    try:
        last = json.load(open(SCHEDULER_STATE)).get("last_run")
        age = (datetime.now() - datetime.fromisoformat(last)).total_seconds() / 60
        if age > 10:
            problems.append(f"ntfy-scheduler last ran {age:.0f} min ago")
    except Exception as exc:
        problems.append(f"ntfy-scheduler state unreadable: {exc}")

    disk = shutil.disk_usage("/")
    used = disk.used / disk.total * 100
    if used > 95:
        problems.append(f"Disk {used:.0f}% full ({disk.free / 1e9:.0f} GB free)")

    if problems:
        title, body, prio = f"Server: {len(problems)} problem(s)", "\n".join(f"- {p}" for p in problems), "high"
    elif datetime.now().weekday() == 0:
        title, body, prio = "Server: all green", f"No failed units, vault syncing, disk {used:.0f}% used.", "low"
    else:
        print("all green")
        sys.exit(0)
    print(title); print(body)
    req = urllib.request.Request(NTFY, data=body.encode(), method="POST",
                                 headers={"Title": title, "Priority": prio, "Tags": "desktop_computer"})
    urllib.request.urlopen(req, timeout=15)
  '';
in {
  systemd.services.server-health-digest = {
    description = "Daily server health push (failed units, vault sync, scheduler, disk)";
    after = ["network-online.target" "ntfy-sh.service" "syncthing.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      # so `systemctl --user --failed` reaches matth's user manager
      Environment = "XDG_RUNTIME_DIR=/run/user/1000";
      ExecStart = "${digest}";
    };
  };
  systemd.timers.server-health-digest = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 08:00:00";
      Persistent = true;
    };
  };
}
