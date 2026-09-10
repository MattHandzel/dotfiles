#!/usr/bin/env python3
"""reboot-state: save what you were working on, reboot, pick what comes back.

    reboot-state save [--name NAME]      snapshot Claude Code sessions, tmux shells, windows
    reboot-state reboot [--name NAME]    save, mark a restore as pending, then systemctl reboot
    reboot-state restore [SNAPSHOT]      pick items to bring back (gum multi-select; Claude preselected)
    reboot-state restore --dry-run       print the launch commands instead of running them
    reboot-state list | show [SNAPSHOT]  browse snapshots
    reboot-state login                   Hyprland exec-once hook: opens the picker only if a
                                         reboot was requested through this tool

State lives in ~/.local/state/reboot-state/. Snapshots are never deleted by the tool;
prune by hand. Nothing is restored unless you select it: rebooting to free memory and
then bringing back two Claude sessions is the normal path.

Sources: ~/.claude/sessions/<pid>.json (session id + cwd of every live Claude process),
/proc (args, parents), tmux (both the `hypr` socket kitty uses and the default socket),
hyprctl clients (workspace of the kitty window that hosts each tmux client).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
STATE = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "reboot-state"
SNAPS = STATE / "snapshots"
PENDING = STATE / "pending-restore"
CLAUDE_SESSIONS = HOME / ".claude/sessions"
CLAUDE_PROJECTS = HOME / ".claude/projects"
# tmux servers are addressed by SOCKET PATH, never by -L name: Hyprland-launched kitty runs
# `tmux -L hypr` with no TMUX_TMPDIR (-> /tmp/tmux-UID/hypr), while login shells here export
# TMUX_TMPDIR=/run/user/UID, so the same -L name resolves to two different servers.
UID = os.getuid()
DEFAULT_SOCKET = f"/tmp/tmux-{UID}/hypr"


def tmux_sockets() -> list[str]:
    seen, out = set(), []
    dirs = [Path(f"/tmp/tmux-{UID}")]
    for var in ("TMUX_TMPDIR", "XDG_RUNTIME_DIR"):
        v = os.environ.get(var)
        if v:
            dirs.append(Path(v) / f"tmux-{UID}")
    for d in dirs:
        if not d.is_dir():
            continue
        for sock in d.iterdir():
            if sock.is_socket():
                rp = str(sock.resolve())
                if rp not in seen:
                    seen.add(rp)
                    out.append(rp)
    return out


# ----------------------------------------------------------------------------- helpers
def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def hyprctl_env():
    env = dict(os.environ)
    if "HYPRLAND_INSTANCE_SIGNATURE" not in env:
        rt = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "hypr"
        try:
            sigs = sorted(rt.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
            if sigs:
                env["HYPRLAND_INSTANCE_SIGNATURE"] = sigs[0].name
        except OSError:
            pass
    return env


def hypr_clients():
    if not shutil.which("hyprctl"):
        return []
    r = run(["hyprctl", "clients", "-j"], env=hyprctl_env())
    if r.returncode != 0:
        return []
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return []


def hypr_dispatch(cmd: str, workspace) -> bool:
    if not shutil.which("hyprctl"):
        return False
    rule = f"[workspace {workspace} silent] " if workspace else ""
    r = run(["hyprctl", "dispatch", "exec", rule + cmd], env=hyprctl_env())
    return r.returncode == 0 and "ok" in r.stdout


def proc_alive(pid: int) -> bool:
    return Path(f"/proc/{pid}").exists()


def proc_cmdline(pid: int) -> list[str]:
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().decode(errors="replace").split("\0")[:-1]
    except OSError:
        return []


def proc_ppid(pid: int) -> int | None:
    try:
        stat = Path(f"/proc/{pid}/stat").read_text()
        return int(stat.rsplit(")", 1)[1].split()[1])
    except (OSError, IndexError, ValueError):
        return None


def ancestors(pid: int) -> list[int]:
    out = []
    while pid and pid > 1 and len(out) < 40:
        pid = proc_ppid(pid)
        if pid:
            out.append(pid)
    return out


def tmux(socket, *args):
    """socket is a path; None = DEFAULT_SOCKET."""
    sock = socket or DEFAULT_SOCKET
    Path(sock).parent.mkdir(mode=0o700, exist_ok=True)
    return run(["tmux", "-S", sock] + list(args))


def tmux_panes():
    """All panes on all sockets: dict pane_pid -> info."""
    panes = {}
    fmt = "#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_title}\t#{window_name}"
    for sock in tmux_sockets():
        r = tmux(sock, "list-panes", "-a", "-F", fmt)
        if r.returncode != 0:
            continue
        for line in r.stdout.splitlines():
            parts = line.split("\t")
            if len(parts) < 8:
                continue
            s, w, p, pid, cmd, path, title, wname = parts[:8]
            panes[int(pid)] = dict(socket=sock, session=s, window=int(w), pane=int(p), cmd=cmd,
                                   cwd=path, title=title, window_name=wname)
    return panes


def tmux_client_pids():
    """Map tmux session name -> pid of an attached client process (to find its kitty window)."""
    out = {}
    for sock in tmux_sockets():
        r = tmux(sock, "list-clients", "-F", "#{client_pid}\t#{client_session}")
        if r.returncode != 0:
            continue
        for line in r.stdout.splitlines():
            pid, sess = line.split("\t")[:2]
            out.setdefault((sock, sess), int(pid))
    return out


def workspace_of_pid(pid: int, clients) -> tuple[str | None, str | None]:
    """Workspace + class of the Hyprland window whose pid is an ancestor of pid."""
    by_pid = {c.get("pid"): c for c in clients}
    for a in [pid] + ancestors(pid):
        c = by_pid.get(a)
        if c:
            return str(c["workspace"]["name"]), c.get("class")
    return None, None


def claude_title(session_id: str, cwd: str) -> str:
    """First real user prompt of the transcript, as a title. Cheap: stops at the first hit."""
    slug = re.sub(r"[^A-Za-z0-9]", "-", cwd)
    f = CLAUDE_PROJECTS / slug / f"{session_id}.jsonl"
    if not f.exists():
        return ""
    try:
        with f.open(errors="replace") as fh:
            for i, line in enumerate(fh):
                if i > 2000:
                    break
                if '"type":"user"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except json.JSONDecodeError:
                    continue
                c = d.get("message", {}).get("content")
                if isinstance(c, list):
                    c = " ".join(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
                if not isinstance(c, str):
                    continue
                t = " ".join(c.split())
                if t and not t.startswith("<"):
                    return t[:90]
    except OSError:
        pass
    return ""


def transcript_exists(session_id: str, cwd: str) -> bool:
    slug = re.sub(r"[^A-Za-z0-9]", "-", cwd)
    return (CLAUDE_PROJECTS / slug / f"{session_id}.jsonl").exists()


def strip_resume_args(args: list[str]) -> list[str]:
    out, skip = [], False
    for a in args[1:]:
        if skip:
            skip = False
            continue
        if a in ("--resume", "-r", "--session-id"):
            skip = True
            continue
        if a in ("-c", "--continue"):
            continue
        out.append(a)
    return out


def git_dirty(cwd: str) -> int | None:
    if not Path(cwd, ".git").exists() and run(["git", "-C", cwd, "rev-parse", "--git-dir"]).returncode != 0:
        return None
    r = run(["git", "-C", cwd, "status", "--porcelain"])
    return len(r.stdout.splitlines()) if r.returncode == 0 else None


def rel_time(ts: float) -> str:
    d = time.time() - ts
    for unit, secs in (("d", 86400), ("h", 3600), ("m", 60)):
        if d >= secs:
            return f"{int(d // secs)}{unit} ago"
    return "just now"


def short(path: str) -> str:
    return path.replace(str(HOME), "~")


# ----------------------------------------------------------------------------- save
def collect() -> dict:
    clients = hypr_clients()
    panes = tmux_panes()
    tmux_clients = tmux_client_pids()
    items = []

    # --- Claude Code sessions (authoritative: the per-pid session files)
    seen_pids = set()
    for f in sorted(CLAUDE_SESSIONS.glob("*.json")):
        if "sync-conflict" in f.name:
            continue
        try:
            d = json.loads(f.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        pid = d.get("pid")
        if not pid or not proc_alive(pid) or pid in seen_pids:
            continue
        cmd = proc_cmdline(pid)
        if not cmd or "claude" not in os.path.basename(cmd[0]):
            continue
        seen_pids.add(pid)
        cwd = d.get("cwd") or os.readlink(f"/proc/{pid}/cwd")
        sid = d.get("sessionId")
        pane = next((panes[p] for p in [pid] + ancestors(pid) if p in panes), None)
        # Inside tmux the process tree stops at the tmux server, so locate the kitty window
        # through the session's attached client instead.
        cpid = tmux_clients.get((pane["socket"], pane["session"])) if pane else None
        ws, wclass = workspace_of_pid(cpid or pid, clients)
        title = (pane or {}).get("title", "")
        title = title.lstrip("✳ ").strip() if title.startswith("✳") else ""
        items.append(dict(
            kind="claude", id=f"claude:{sid}", session_id=sid, cwd=cwd, pid=pid,
            args=strip_resume_args(cmd), started_at=(d.get("startedAt") or 0) / 1000,
            version=d.get("version"), title=title or claude_title(sid, cwd),
            tmux=pane and dict(socket=pane["socket"], session=pane["session"], window=pane["window"],
                               window_name=pane["window_name"]),
            workspace=ws, git_dirty=git_dirty(cwd),
        ))
    claude_pane_keys = {(i["tmux"]["socket"], i["tmux"]["session"], i["tmux"]["window"]) for i in items if i.get("tmux")}

    # --- other tmux panes (shells, servers) -> "shell" items, one per window
    seen_windows = set()
    for pid, p in panes.items():
        key = (p["socket"], p["session"], p["window"])
        if key in claude_pane_keys or key in seen_windows:
            continue
        seen_windows.add(key)
        cpid = tmux_clients.get((p["socket"], p["session"]))
        ws = workspace_of_pid(cpid, clients)[0] if cpid else None
        items.append(dict(
            kind="shell", id=f"shell:{p['socket']}:{p['session']}:{p['window']}", cwd=p["cwd"],
            cmd=p["cmd"], title=p["title"][:90], tmux=dict(socket=p["socket"], session=p["session"],
                                                            window=p["window"], window_name=p["window_name"]),
            workspace=ws,
        ))

    # --- GUI apps (non-terminal windows on numbered workspaces)
    seen_classes = set()
    for c in clients:
        cls = c.get("class") or ""
        wsname = str(c["workspace"]["name"])
        if not c.get("mapped") or cls.lower() in ("kitty", "") or cls in seen_classes:
            continue
        if wsname.startswith("special:"):  # tray-style apps parked on a special workspace autostart themselves
            continue
        seen_classes.add(cls)
        items.append(dict(kind="app", id=f"app:{cls}", app_class=cls, title=(c.get("title") or "")[:80],
                          workspace=wsname, pid=c.get("pid")))

    return dict(version=1, created_at=time.time(), host=os.uname().nodename, items=items)


def save(name: str | None) -> Path:
    SNAPS.mkdir(parents=True, exist_ok=True)
    snap = collect()
    n_claude = sum(1 for i in snap["items"] if i["kind"] == "claude")
    if not snap["items"]:
        sys.exit("reboot-state: nothing to save (no Claude sessions, tmux panes, or windows found)")
    stamp = dt.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    snap["name"] = name or stamp
    path = SNAPS / f"{stamp}{'_' + re.sub(r'[^A-Za-z0-9_-]+', '-', name) if name else ''}.json"
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(snap, indent=1))
    tmp.replace(path)
    latest = SNAPS / "latest.json"
    if latest.is_symlink() or latest.exists():
        latest.unlink()
    latest.symlink_to(path.name)
    print(f"saved {path}  ({n_claude} claude, {len(snap['items']) - n_claude} other)")
    return path


# ----------------------------------------------------------------------------- restore
def load(arg: str | None) -> tuple[dict, Path]:
    if arg and Path(arg).exists():
        p = Path(arg)
    elif arg:
        matches = sorted(SNAPS.glob(f"*{arg}*.json"))
        if not matches:
            sys.exit(f"no snapshot matching {arg!r}; see `reboot-state list`")
        p = matches[-1]
    else:
        p = SNAPS / "latest.json"
        if not p.exists():
            sys.exit("no snapshots yet; run `reboot-state save`")
    return json.loads(p.read_text()), p.resolve()


def label(i: dict, live_claude: set[str]) -> str:
    where = []
    if i.get("tmux"):
        where.append(f"tmux {i['tmux']['session']}:{i['tmux']['window']}")
    if i.get("workspace"):
        where.append(f"ws {i['workspace']}")
    loc = ", ".join(where)
    if i["kind"] == "claude":
        flags = []
        if i["session_id"] in live_claude:
            flags.append("RUNNING")
        if not transcript_exists(i["session_id"], i["cwd"]):
            flags.append("no transcript")
        if i.get("git_dirty"):
            flags.append(f"{i['git_dirty']} dirty")
        f = f"  [{'; '.join(flags)}]" if flags else ""  # no commas: gum --selected splits on them
        return f"claude  {i.get('title') or '(untitled)'}  —  {short(i['cwd'])}  ({loc}; started {rel_time(i['started_at'])}){f}"
    if i["kind"] == "shell":
        return f"shell   {i.get('cmd', '')}: {i.get('title') or ''}  —  {short(i['cwd'])}  ({loc})"
    return f"app     {i['app_class']}  —  {i.get('title', '')}  (ws {i.get('workspace')})"


def live_claude_ids() -> set[str]:
    out = set()
    for f in CLAUDE_SESSIONS.glob("*.json"):
        try:
            d = json.loads(f.read_text())
            if d.get("pid") and proc_alive(d["pid"]):
                out.add(d.get("sessionId"))
        except (OSError, json.JSONDecodeError):
            pass
    return out


def pick(items: list[dict], preselect: list[str], header: str) -> list[dict]:
    live = live_claude_ids()
    labels = [label(i, live) for i in items]
    if not sys.stdin.isatty() or not shutil.which("gum"):
        print(header)
        for n, l in enumerate(labels, 1):
            print(f"  {n:2d}. {l}")
        raw = input("numbers to restore (space-separated, 'all', or empty for none): ").strip()
        if raw == "all":
            return items
        idx = {int(x) for x in raw.split() if x.isdigit()}
        return [i for n, i in enumerate(items, 1) if n in idx]
    cmd = ["gum", "choose", "--no-limit", "--height", str(min(len(labels) + 2, 30)), "--header", header,
           "--cursor-prefix", "[ ] ", "--selected-prefix", "[x] ", "--unselected-prefix", "[ ] "]
    for p in preselect:
        cmd += ["--selected", p]
    r = subprocess.run(cmd + labels, capture_output=True, text=True)
    if r.returncode != 0:
        return []
    chosen = set(r.stdout.splitlines())
    return [i for i, l in zip(items, labels) if l in chosen]


APP_BIN = {"zen-beta": "zen-beta", "zen": "zen", "google-chrome": "google-chrome-stable", "Beeper": "beeper",
           "Slack": "slack", "obsidian": "obsidian", "com.anthropic.Claude": "claude-desktop", "spotify": "spotify"}


def app_command(cls: str) -> str | None:
    if cls in APP_BIN and shutil.which(APP_BIN[cls]):
        return APP_BIN[cls]
    lowfull = cls.lower()
    if lowfull.startswith("chrome-") and "__" in lowfull:  # chrome PWA windows: chrome-<host>__-Default
        host = lowfull[len("chrome-"):].split("__")[0]
        return f"google-chrome-stable --app=https://{host}"
    low = lowfull.rsplit(".", 1)[-1]
    if shutil.which(low):
        return low
    apps = Path("/etc/profiles/per-user") / os.environ.get("USER", "") / "share/applications"
    for d in (apps, HOME / ".nix-profile/share/applications", HOME / ".local/share/applications"):
        if d.is_dir():
            for f in d.glob("*.desktop"):
                if f.stem.lower() == cls.lower() and shutil.which("gtk-launch"):
                    return f"gtk-launch {f.stem}"
    return None


def restore(items: list[dict], dry: bool) -> None:
    live = live_claude_ids()
    plan: list[tuple[str, str]] = []  # (description, shell command) executed in order
    # Group tmux-hosted items by (socket, session) so each session is created once and attached once.
    groups: dict[tuple, list[dict]] = {}
    loose: list[dict] = []
    for i in items:
        if i["kind"] == "claude" and i["session_id"] in live:
            plan.append((f"skip: claude {i.get('title')!r} is already running", ""))
            continue
        if i["kind"] in ("claude", "shell"):
            t = i.get("tmux") or dict(socket=DEFAULT_SOCKET, session=Path(i["cwd"]).name or "main", window=0)
            groups.setdefault((t["socket"], t["session"]), []).append(i)
        else:
            loose.append(i)

    for (sock, sess), members in groups.items():
        if sock and not sock.startswith("/"):  # legacy -L name from an older snapshot
            sock = f"/tmp/tmux-{UID}/{sock}"
        sock = sock or DEFAULT_SOCKET
        L = f"-S {shlex.quote(sock)} "
        exists = tmux(sock, "has-session", "-t", f"={sess}").returncode == 0
        for n, i in enumerate(sorted(members, key=lambda m: (m.get("tmux") or {}).get("window", 0))):
            cwd = i["cwd"] if Path(i["cwd"]).is_dir() else str(HOME)
            if cwd != i["cwd"]:
                plan.append((f"note: {short(i['cwd'])} is gone, using ~", ""))
            if i["kind"] == "claude":
                inner = "claude " + " ".join(shlex.quote(a) for a in i.get("args", [])) + f" --resume {shlex.quote(i['session_id'])}"
                # keep the pane alive after claude exits so the tmux window doesn't vanish on a crash
                inner = f"{inner}; exec $SHELL"
                wname = shlex.quote((i.get("title") or "claude")[:24])
            else:
                inner = ""
                wname = shlex.quote((i.get("tmux") or {}).get("window_name") or Path(cwd).name)
            body = f" {shlex.quote(inner)}" if inner else ""
            if not exists and n == 0:
                plan.append((f"tmux session {sess}: {i['kind']} in {short(cwd)}",
                             f"tmux {L}new-session -d -s {shlex.quote(sess)} -n {wname} -c {shlex.quote(cwd)}{body}"))
                exists = True
            else:
                plan.append((f"tmux window in {sess}: {i['kind']} in {short(cwd)}",
                             f"tmux {L}new-window -d -t {shlex.quote(sess)}: -n {wname} -c {shlex.quote(cwd)}{body}"))
        ws = next((m.get("workspace") for m in members if m.get("workspace")), None)
        attach = f"kitty -e tmux {L}attach -t {shlex.quote(sess)}"
        already_attached = tmux(sock, "list-clients", "-t", f"={sess}").stdout.strip() != ""
        if already_attached:
            plan.append((f"tmux session {sess} already has a client; not opening another kitty", ""))
        else:
            plan.append((f"open kitty attached to {sess}" + (f" on workspace {ws}" if ws else ""), f"HYPR\x1f{ws or ''}\x1f{attach}"))

    for i in loose:
        cmd = app_command(i["app_class"])
        if not cmd:
            plan.append((f"skip: don't know how to launch {i['app_class']}", ""))
            continue
        plan.append((f"launch {i['app_class']} on workspace {i.get('workspace')}", f"HYPR\x1f{i.get('workspace') or ''}\x1f{cmd}"))

    for desc, cmd in plan:
        print(("  " if cmd else "  · ") + desc)
        if dry or not cmd:
            if dry and cmd:
                print("      $ " + (cmd.replace("\x1f", " ") if cmd.startswith("HYPR") else cmd))
            continue
        if cmd.startswith("HYPR\x1f"):
            _, ws, real = cmd.split("\x1f", 2)
            if not hypr_dispatch(real, ws or None):
                subprocess.Popen(real, shell=True, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            Path(DEFAULT_SOCKET).parent.mkdir(mode=0o700, exist_ok=True)
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
            if r.returncode != 0:
                print("      failed: " + (r.stderr.strip() or r.stdout.strip()))
        time.sleep(0.3)


# ----------------------------------------------------------------------------- commands
def cmd_save(a):
    save(a.name)


def cmd_reboot(a):
    p = save(a.name)
    PENDING.write_text(str(p))
    if not a.yes:
        ok = subprocess.run(["gum", "confirm", f"Saved {p.name}. Reboot now?"]).returncode == 0 if shutil.which("gum") \
            else input("Reboot now? [y/N] ").strip().lower() == "y"
        if not ok:
            print("not rebooting; snapshot kept and restore stays pending (run `reboot-state restore` any time)")
            return
    subprocess.run(["systemctl", "reboot"])


def cmd_restore(a):
    snap, path = load(a.snapshot)
    items = snap["items"]
    if a.only:
        items = [i for i in items if i["kind"] in a.only]
    if not items:
        sys.exit("snapshot has no items of that kind")
    if a.all:
        chosen = items
    elif a.none:
        chosen = []
    else:
        live = live_claude_ids()
        pre = [label(i, live) for i in items if i["kind"] == "claude" and i["session_id"] not in live]
        header = f"{path.name} · {snap.get('name')} · saved {rel_time(snap['created_at'])} — space toggles, ctrl+a all, enter restores the checked ones, esc restores nothing"
        chosen = pick(items, pre, header)
    if PENDING.exists() and not a.dry_run:
        PENDING.unlink()
    if not chosen:
        print("nothing selected; nothing restored (snapshot kept)")
        return
    restore(chosen, a.dry_run)
    if not a.dry_run:
        print(f"restored {len(chosen)} item(s). Re-run `reboot-state restore {path.name}` for the rest.")


def cmd_list(a):
    snaps = sorted(SNAPS.glob("*.json"))
    if not snaps:
        print("no snapshots")
        return
    for p in snaps:
        if p.name == "latest.json":
            continue
        try:
            s = json.loads(p.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        kinds = {}
        for i in s["items"]:
            kinds[i["kind"]] = kinds.get(i["kind"], 0) + 1
        mark = " (latest)" if (SNAPS / "latest.json").resolve() == p.resolve() else ""
        print(f"{p.name}{mark}  {rel_time(s['created_at'])}  " + " ".join(f"{k}={v}" for k, v in sorted(kinds.items())))


def cmd_show(a):
    snap, path = load(a.snapshot)
    live = live_claude_ids()
    print(f"{path.name} · saved {rel_time(snap['created_at'])} on {snap.get('host')}")
    for i in snap["items"]:
        print("  " + label(i, live))


def cmd_login(a):
    if not PENDING.exists():
        return
    snap = PENDING.read_text().strip()
    # A centered floating kitty (Hyprland rule on title float_kitty) running the picker.
    inner = f"reboot-state restore {shlex.quote(snap)}; echo; read -n1 -p 'press any key to close'"
    if not hypr_dispatch(f"kitty --title float_kitty -e bash -c {shlex.quote(inner)}", None):
        subprocess.Popen(["kitty", "--title", "float_kitty", "-e", "bash", "-c", inner], start_new_session=True)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="reboot-state", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("save"); s.add_argument("--name"); s.set_defaults(fn=cmd_save)
    s = sub.add_parser("reboot"); s.add_argument("--name"); s.add_argument("-y", "--yes", action="store_true"); s.set_defaults(fn=cmd_reboot)
    s = sub.add_parser("restore"); s.add_argument("snapshot", nargs="?"); s.add_argument("--dry-run", action="store_true")
    s.add_argument("--all", action="store_true"); s.add_argument("--none", action="store_true")
    s.add_argument("--only", action="append", choices=["claude", "shell", "app"]); s.set_defaults(fn=cmd_restore)
    s = sub.add_parser("list"); s.set_defaults(fn=cmd_list)
    s = sub.add_parser("show"); s.add_argument("snapshot", nargs="?"); s.set_defaults(fn=cmd_show)
    s = sub.add_parser("login"); s.set_defaults(fn=cmd_login)
    a = ap.parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
