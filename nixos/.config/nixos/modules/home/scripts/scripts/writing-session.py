#!/usr/bin/env python3
"""Track drafting velocity for a writing session and report it as waybar JSON.

The point (https://sashachapin.substack.com/p/write-faster-130): keep the words
coming faster than the inner critic can object. Chapin's threshold is 500 words
per HOUR, which is what the readout reports — the same unit as the target, so
"am I clearing it?" needs no arithmetic. That makes a live readout useful
rather than vain: it tells you when you have stalled out into "paralyzing
cogitation", which is the failure this is for.

GLOBAL BY DEFAULT, and global means "whatever editor you use". Words are found
two ways, because relying on either alone silently collects nothing:

  1. A start-time word-count snapshot of the writing roots, re-checked by a
     periodic stat sweep. This is what makes Obsidian — or any other program
     that writes a file — count.
  2. Live word counts published by an editor for UNSAVED buffers (nvim does
     this). Instant, but only for editors that opt in.

An earlier version had only (2), and a real session recorded `files: []` and
0 words because nothing ever published. Measured costs on the actual vault
(13,666 files, 126 MB) drove the split: the snapshot read is ~2.1s (fine once,
at an explicit `start`) but a full stat sweep is ~420ms, which is far too heavy
to run at waybar's 5s poll — hence SCAN_INTERVAL, with the live overlay
covering the gap so typing still reads as instant in nvim.

Deliberately daemonless. `status` performs the sampling as a side effect, and
waybar already polls it every few seconds, so the widget IS the sampler. One
less unit to keep alive, and nothing to leak when a session is abandoned.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

# A gap longer than this means sampling stopped (laptop asleep, waybar dead,
# session abandoned) rather than that the writer was thinking. Time inside such
# a gap is not writing time and must not dilute the average.
MAX_SAMPLE_GAP = 120.0

# Thinking time counts against you — that is the entire premise. But once no
# word has landed for this long you have stopped writing, and continuing to
# accrue would turn the readout into a measure of how long ago you quit.
IDLE_AFTER = 300.0

# Chapin's floor, in words per hour.
TARGET_WPH = 500.0

# Nobody types 4 words/second sustained. A per-file jump above this rate is a
# machine write — Syncthing landing a remote copy, an agent appending to a
# note, a template expanding — so it is rebased into the baseline instead of
# being counted. Without this, one background write invents thousands of words.
MAX_HUMAN_WPS = 4.0
MACHINE_WRITE_SLACK = 50

# Seconds between full stat sweeps of the roots. The sweep costs ~420ms on the
# real vault, so running it at waybar's poll rate would burn ~8% of a core
# forever; at 20s it is ~2% and saved files still show up promptly.
SCAN_INTERVAL = 20.0

DEFAULT_ROOTS = ["~/Obsidian/Main"]
SKIP_DIRS = {".git", ".obsidian", ".trash", ".stversions", "node_modules",
             "__pycache__", ".stfolder"}
PROSE_SUFFIXES = {".md", ".markdown", ".txt", ".org", ".rst", ".tex", ".norg"}


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "writing-session"


def live_dir() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    return Path(base) / "writing-session-live"


def session_path() -> Path:
    return state_dir() / "session.json"


def baseline_path() -> Path:
    return state_dir() / "baseline.json"


def history_path() -> Path:
    return state_dir() / "history.jsonl"


def count_words(text: str) -> int:
    """Prose words. YAML frontmatter is metadata, not drafting, so it is cut."""
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            nl = text.find("\n", end + 1)
            text = text[nl + 1:] if nl != -1 else ""
    return len(text.split())


def file_words(path: str) -> int:
    try:
        return count_words(Path(path).read_text(encoding="utf-8", errors="replace"))
    except (OSError, ValueError):
        return 0


def walk_roots(roots: list[str]):
    """Yield (path, mtime) for every prose file under the roots."""
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames
                           if d not in SKIP_DIRS and not d.startswith(".")]
            for name in filenames:
                if Path(name).suffix.lower() not in PROSE_SUFFIXES:
                    continue
                full = os.path.join(dirpath, name)
                try:
                    yield full, os.stat(full).st_mtime
                except OSError:
                    continue


def live_file_for(path: str) -> Path:
    digest = hashlib.sha256(path.encode("utf-8")).hexdigest()[:16]
    return live_dir() / f"{digest}.json"


def read_overlays() -> dict[str, tuple[int, float]]:
    """{path: (words, ts)} for editor-published unsaved buffers, fresh only."""
    out: dict[str, tuple[int, float]] = {}
    now = time.time()
    try:
        entries = list(live_dir().iterdir())
    except OSError:
        return out
    for entry in entries:
        if entry.suffix != ".json":
            continue
        try:
            data = json.loads(entry.read_text(encoding="utf-8"))
            ts = float(data["ts"])
            # A stale overlay left by a closed editor must not freeze the count.
            if now - ts < MAX_SAMPLE_GAP:
                out[str(data["path"])] = (int(data["words"]), ts)
        except (OSError, ValueError, KeyError, TypeError):
            continue
    return out


# Every key sample()/metrics() dereference. A session file written by an older
# build would otherwise raise mid-poll and take the waybar module down with it —
# so an unreadable-or-foreign session is discarded rather than trusted.
REQUIRED_KEYS = frozenset(
    {"started_at", "files", "roots", "last_sample_at", "last_change_at",
     "active_seconds", "last_scan_at"}
)


def load() -> dict | None:
    try:
        session = json.loads(session_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    if not isinstance(session, dict) or not REQUIRED_KEYS <= session.keys():
        session_path().unlink(missing_ok=True)
        baseline_path().unlink(missing_ok=True)
        return None
    return session


def save(session: dict) -> None:
    state_dir().mkdir(parents=True, exist_ok=True)
    tmp = session_path().with_suffix(".json.tmp")
    tmp.write_text(json.dumps(session), encoding="utf-8")
    tmp.replace(session_path())  # atomic: waybar reads this constantly


_baseline_cache: dict | None = None


def baseline_map() -> dict:
    """{path: [mtime, words]} captured at session start. Loaded lazily: it is
    only needed when a file changes for the first time, which is rare."""
    global _baseline_cache
    if _baseline_cache is None:
        try:
            _baseline_cache = json.loads(baseline_path().read_text(encoding="utf-8"))
        except (OSError, ValueError):
            _baseline_cache = {}
    return _baseline_cache


def under_roots(path: str, roots: list[str]) -> bool:
    return any(os.path.commonpath([path, r]) == r for r in roots
               if os.path.isabs(path))


def human_allowance(elapsed: float) -> float:
    """Most words a person could plausibly have typed in `elapsed` seconds."""
    return MAX_HUMAN_WPS * max(elapsed, 1.0) + MACHINE_WRITE_SLACK


def observe(session: dict, path: str, words: int, now: float,
            window: float) -> bool:
    """Record a file's current word count. Returns True if words changed.

    A file's baseline is what it held before the session, so prose written
    earlier is never counted as new. For a file created during the session the
    baseline is 0 — every word in it is genuinely new.

    `window` is how long this file has had to accumulate words unobserved: the
    gap since the previous sweep/overlay read. It bounds what a human could
    have typed, and the machine-write guard applies on the FIRST sighting for
    exactly that reason. Without it, a file that did not exist at the last
    sweep and holds 5,000 words at this one is credited in full — which is how
    one agent-written capture note turned a real 11-minute session into a
    reported 507 wpm.
    """
    entry = session["files"].get(path)
    if entry is None:
        snapshot = baseline_map().get(path)
        if snapshot is not None:
            baseline = int(snapshot[1])
        elif under_roots(path, session["roots"]):
            baseline = 0  # created after the snapshot => all of it is new
        else:
            baseline = words  # outside the roots; first sighting is the best we have
        # A file cannot have been observed before it existed, so its unobserved
        # window is at most the time since the session began.
        first_window = min(window, now - session["started_at"])
        if words - baseline > human_allowance(first_window):
            baseline = words  # machine write: absorb, never count
        session["files"][path] = {"baseline": baseline, "current": words,
                                  "seen": now}
        return words != baseline

    delta = words - entry["current"]
    if delta == 0:
        entry["seen"] = now
        return False

    # Allowance is per-file elapsed time, not the sample gap: a file first seen
    # by a 20s sweep legitimately carries 20s of typing.
    elapsed = now - entry.get("seen", now)
    if delta > human_allowance(elapsed):
        entry["baseline"] += delta  # machine write: absorb, never count
        entry["current"] = words
        entry["seen"] = now
        return False

    entry["current"] = words
    entry["seen"] = now
    return True


def sample(session: dict, now: float | None = None) -> dict:
    """Fold current word counts into the session's active-time accounting."""
    now = time.time() if now is None else now
    words_moved = False

    # (2) editor overlays — instant, unsaved buffers included
    overlay = read_overlays()
    overlay_window = now - session["last_sample_at"]
    for path, (words, _ts) in overlay.items():
        if observe(session, path, words, now, overlay_window):
            words_moved = True

    # (1) periodic sweep of the roots — catches every other program
    scan_window = now - session["last_scan_at"]
    if scan_window >= SCAN_INTERVAL:
        base = baseline_map()
        for path, mtime in walk_roots(session["roots"]):
            if path in overlay:
                continue  # the editor's live count is fresher than the file
            snapshot = base.get(path)
            known = session["files"].get(path)
            if snapshot is not None and known is None and mtime <= float(snapshot[0]):
                continue  # untouched since the session began
            if observe(session, path, file_words(path), now, scan_window):
                words_moved = True
        session["last_scan_at"] = now

    gap = now - session["last_sample_at"]
    stalled_for = now - session["last_change_at"]

    # Accrue only real, attended writing time (see the constants above).
    if 0 < gap <= MAX_SAMPLE_GAP and (words_moved or stalled_for <= IDLE_AFTER):
        session["active_seconds"] += gap

    if words_moved:
        session["last_change_at"] = now
    session["last_sample_at"] = now
    return session


def metrics(session: dict) -> dict:
    # Per-file max(0, …): deleting in one file must not silently cancel out
    # words drafted in another.
    added = sum(max(0, f["current"] - f["baseline"]) for f in session["files"].values())
    touched = sum(1 for f in session["files"].values() if f["current"] != f["baseline"])
    active = session["active_seconds"]
    wpm = (added / (active / 60.0)) if active >= 30 else 0.0
    return {
        "words_added": added,
        "active_seconds": active,
        "elapsed_seconds": time.time() - session["started_at"],
        "files": touched,
        "wpm": wpm,
        "wph": wpm * 60.0,
        "on_target": wpm * 60.0 >= TARGET_WPH,
    }


def fmt_duration(seconds: float) -> str:
    seconds = int(seconds)
    h, m = seconds // 3600, (seconds % 3600) // 60
    return f"{h}h{m:02d}m" if h else f"{m}m"


def cmd_start(args: argparse.Namespace) -> int:
    if load() and not args.force:
        print("writing-session: a session is already running (use --force to restart)",
              file=sys.stderr)
        return 1

    roots = [str(Path(r).expanduser().resolve())
             for r in (args.root or DEFAULT_ROOTS)]
    roots = [r for r in roots if os.path.isdir(r)]

    now = time.time()
    snapshot = {path: [mtime, count_words(_read(path))]
                for path, mtime in walk_roots(roots)}
    state_dir().mkdir(parents=True, exist_ok=True)
    baseline_path().write_text(json.dumps(snapshot), encoding="utf-8")

    session = {
        "started_at": now,
        "roots": roots,
        "files": {},
        "last_sample_at": now,
        "last_change_at": now,
        "last_scan_at": now,
        "active_seconds": 0.0,
        "label": args.label or "global",
    }
    for p in args.paths:
        full = str(Path(p).expanduser().resolve())
        # window 0: an explicitly-named file's existing prose is baseline, not
        # words drafted this session.
        observe(session, full, file_words(full), now, 0.0)
    save(session)

    print(f"Writing session started — watching {len(snapshot)} file(s) in "
          f"{len(roots)} root(s), plus any editor that reports live. "
          f"Target: {TARGET_WPH:.0f} words/hour.")
    return 0


def _read(path: str) -> str:
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except (OSError, ValueError):
        return ""


def cmd_stop(_args: argparse.Namespace) -> int:
    session = load()
    if not session:
        print("writing-session: no session running", file=sys.stderr)
        return 1

    sample(session)
    m = metrics(session)
    record = {
        "started_at": session["started_at"],
        "ended_at": time.time(),
        "label": session.get("label", ""),
        "paths": sorted(p for p, f in session["files"].items()
                        if f["current"] != f["baseline"]),
        **m,
    }
    try:
        state_dir().mkdir(parents=True, exist_ok=True)
        with history_path().open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(record) + "\n")
    except OSError:
        pass  # a lost history line must never cost the user their summary

    session_path().unlink(missing_ok=True)
    baseline_path().unlink(missing_ok=True)
    print(f"Session ended: {m['words_added']} words across {m['files']} file(s) in "
          f"{fmt_duration(m['active_seconds'])} of writing → {m['wph']:.0f} wph "
          f"({'on target' if m['on_target'] else 'under ' + str(int(TARGET_WPH))}).")
    return 0


def cmd_toggle(args: argparse.Namespace) -> int:
    """One entry point for a launcher/hotkey: start if idle, stop if running."""
    return cmd_stop(args) if load() else cmd_start(args)


def cmd_status(args: argparse.Namespace) -> int:
    session = load()
    if not session:
        # Empty text collapses the waybar module when nothing is being written.
        if args.json:
            print(json.dumps({"text": "", "class": ["idle"], "tooltip": "No writing session"}))
        else:
            print("no session")
        return 0

    sample(session)
    save(session)
    m = metrics(session)

    if not args.json:
        print(f"{m['wph']:.0f} wph  ({m['words_added']} words, "
              f"{fmt_duration(m['active_seconds'])} writing)")
        return 0

    # Below ~30s of writing the rate is dominated by noise; show the word count
    # instead, so the widget still visibly reacts to typing from the first tick.
    warming = m["active_seconds"] < 30
    text = f"✍ {m['words_added']}w" if warming else f"✍ {round(m['wph'])} wph"
    print(json.dumps({
        "text": text,
        "class": ["active", "warming" if warming else
                  ("on-target" if m["on_target"] else "under-target")],
        "tooltip": "\n".join([
            f"{m['words_added']} words added across {m['files']} file(s)",
            f"{m['wph']:.0f} words/hour (target {TARGET_WPH:.0f})",
            f"{fmt_duration(m['active_seconds'])} writing / {fmt_duration(m['elapsed_seconds'])} elapsed",
            "",
            "Click to end the session",
        ]),
    }))
    return 0


def cmd_live_update(args: argparse.Namespace) -> int:
    """Publish an unsaved buffer's word count (called by the editor).

    Writes only the overlay: `status` is the single writer of session.json, so
    an editor publishing concurrently can never race the sampler.
    """
    path = str(Path(args.path).expanduser().resolve())
    live_dir().mkdir(parents=True, exist_ok=True)
    target = live_file_for(path)
    tmp = target.with_suffix(".tmp")
    tmp.write_text(json.dumps({"path": path, "words": args.words, "ts": time.time()}),
                   encoding="utf-8")
    tmp.replace(target)
    return 0


def cmd_track(args: argparse.Namespace) -> int:
    session = load()
    if not session:
        print("writing-session: no session running", file=sys.stderr)
        return 1
    path = str(Path(args.path).expanduser().resolve())
    observe(session, path, file_words(path), time.time(), 0.0)
    save(session)
    print(f"Tracking {path}")
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    try:
        lines = history_path().read_text(encoding="utf-8").strip().splitlines()
    except OSError:
        print("No sessions recorded yet.")
        return 0

    rows = [json.loads(line) for line in lines if line.strip()][-args.last:]
    if not rows:
        print("No sessions recorded yet.")
        return 0

    print(f"{'date':<17}{'label':<20}{'words':>7}{'writing':>9}{'wph':>7}")
    for r in rows:
        stamp = time.strftime("%Y-%m-%d %H:%M", time.localtime(r["started_at"]))
        label = (r.get("label") or "")[:18]
        # Older history lines predate the wph field; derive it from wpm.
        wph = r.get("wph", r.get("wpm", 0.0) * 60.0)
        print(f"{stamp:<17}{label:<20}{r['words_added']:>7}"
              f"{fmt_duration(r['active_seconds']):>9}{wph:>7.0f}")

    total_added = sum(r["words_added"] for r in rows)
    total_active = sum(r["active_seconds"] for r in rows)
    if total_active > 0:
        avg_wph = total_added / (total_active / 3600.0)
        print(f"\n{len(rows)} sessions · {total_added} words · "
              f"{fmt_duration(total_active)} writing · {avg_wph:.0f} wph avg "
              f"(target {TARGET_WPH:.0f})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="writing-session", description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    for name, help_text in (("start", "begin a session"),
                            ("toggle", "start if idle, stop if running")):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("paths", nargs="*")
        p.add_argument("--root", action="append",
                       help=f"writing root to watch (default: {DEFAULT_ROOTS[0]})")
        p.add_argument("--label", default="")
        p.add_argument("--force", action="store_true", help="restart a running session")
        p.set_defaults(func=cmd_start if name == "start" else cmd_toggle)

    sub.add_parser("stop", help="end the session and log it").set_defaults(func=cmd_stop)

    p_status = sub.add_parser("status", help="sample and report (waybar entry point)")
    p_status.add_argument("--json", action="store_true", help="emit waybar JSON")
    p_status.set_defaults(func=cmd_status)

    p_live = sub.add_parser("live-update", help="publish an unsaved buffer word count")
    p_live.add_argument("path")
    p_live.add_argument("words", type=int)
    p_live.set_defaults(func=cmd_live_update)

    p_track = sub.add_parser("track", help="add a file to the running session")
    p_track.add_argument("path")
    p_track.set_defaults(func=cmd_track)

    p_report = sub.add_parser("report", help="show recent sessions")
    p_report.add_argument("--last", type=int, default=20)
    p_report.set_defaults(func=cmd_report)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
