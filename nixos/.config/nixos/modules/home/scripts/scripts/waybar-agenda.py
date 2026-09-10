#!/usr/bin/env python3
"""Waybar module: what's happening now and what's next.

Reads the cached agenda written by system-wide-focus/resolver/agenda.py. Does no
network I/O of its own, so it is cheap enough to poll every 30s for a live
countdown while the fetcher refreshes from Google every 2 minutes.

Emits waybar JSON: {text, tooltip, class}.
"""

import html
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE = Path(os.environ.get(
    "FOCUS_AGENDA_STATE",
    str(Path.home() / ".local/state/focus/agenda.json"),
))

MAX_TITLE = 26
STALE_AFTER_MIN = 15  # agenda older than this = the fetcher is broken; say so


def shorten(title, limit=MAX_TITLE):
    """Cal.com-style titles are 'Matt Handzel / Alexandra Bates - 30min Meeting'.
    The only informative part is the other person."""
    t = title.strip()
    t = re.sub(r"^\s*Matt Handzel\s*/\s*", "", t)
    t = re.sub(r"\s*[-–]\s*\d+\s*min(ute)?s?\s*(Meeting)?\s*$", "", t, flags=re.I)
    t = re.sub(r"^\s*\[[^\]]*\]\s*", "", t)          # drop [ai-generated] style tags
    t = t.strip(" -–—")
    return (t[: limit - 1] + "…") if len(t) > limit else t


def esc(s):
    """Pango-escape, but leave apostrophes alone (&#x27; renders literally)."""
    return html.escape(s, quote=False)


def human_delta(minutes):
    if minutes < 1:
        return "<1m"
    if minutes < 60:
        return f"{minutes}m"
    h, m = divmod(minutes, 60)
    return f"{h}h{m:02d}m" if m else f"{h}h"


def clock(dt):
    s = dt.astimezone().strftime("%-I:%M%p").lower()
    return s.replace(":00", "")          # 4:30pm stays, 4:00pm -> 4pm


def emit(text, tooltip, cls):
    print(json.dumps({"text": text, "tooltip": tooltip, "class": cls}))
    sys.exit(0)


def main():
    if not STATE.exists():
        emit("󰃰 no agenda", "Agenda cache missing.\nIs calendar-agenda.timer running?", "error")

    try:
        data = json.loads(STATE.read_text())
    except (json.JSONDecodeError, OSError) as exc:
        emit("󰃰 agenda?", f"Could not read agenda: {esc(str(exc))}", "error")

    now = datetime.now(timezone.utc)
    updated = datetime.fromisoformat(data["updated"])
    stale_min = int((now - updated).total_seconds() // 60)

    cur, nxt = data.get("now"), data.get("next")
    conflicts, within = data.get("conflicts", []), data.get("within", [])

    # ---- bar text -------------------------------------------------------
    parts = []
    if cur:
        left = int((datetime.fromisoformat(cur["end"]) - now).total_seconds() // 60)
        parts.append(f"{shorten(cur['title'])} · {human_delta(left)}")
    else:
        parts.append("free")

    if nxt:
        start = datetime.fromisoformat(nxt["start"])
        until = int((start - now).total_seconds() // 60)
        parts.append(f"→ {shorten(nxt['title'])} {clock(start)}")

    text = "󰃰 " + "  ".join(parts)
    if conflicts:
        text += f"  ⚠{len(conflicts) + 1}"

    # ---- class (drives colour in style.nix) -----------------------------
    cls = "normal"
    if stale_min > STALE_AFTER_MIN:
        cls = "stale"
    elif conflicts:
        cls = "conflict"
    elif nxt:
        until = int((datetime.fromisoformat(nxt["start"]) - now).total_seconds() // 60)
        if until <= 5:
            cls = "imminent"
        elif until <= 15:
            cls = "soon"
    elif not cur:
        cls = "free"

    # ---- tooltip --------------------------------------------------------
    lines = []
    if cur:
        end = datetime.fromisoformat(cur["end"])
        left = int((end - now).total_seconds() // 60)
        lines.append(f"<b>Now — {esc(shorten(cur['title'], 48))}</b>")
        lines.append(f"  ends {clock(end)} ({human_delta(left)} left) · {esc(cur['calendar'])}")
        for w in within:
            lines.append(f"  <i>within {esc(shorten(w['title'], 40))}</i>")
    else:
        lines.append("<b>Now — nothing scheduled</b>")

    if conflicts:
        lines.append("")
        lines.append(f"<b>⚠ {len(conflicts)} competing event(s)</b>")
        for c in conflicts:
            s, e = datetime.fromisoformat(c["start"]), datetime.fromisoformat(c["end"])
            lines.append(f"  {clock(s)}–{clock(e)}  {esc(shorten(c['title'], 40))}")

    upcoming = data.get("upcoming", [])
    if upcoming:
        lines.append("")
        lines.append("<b>Coming up</b>")
        for e in upcoming:
            s = datetime.fromisoformat(e["start"])
            until = int((s - now).total_seconds() // 60)
            mark = "󰤙" if e["kind"] == "meeting" else "󰃰"
            lines.append(
                f"  {mark} {clock(s):>7}  {esc(shorten(e['title'], 40))}"
                f"  <i>(in {human_delta(until)})</i>"
            )

    allday = data.get("allday", [])
    if allday:
        lines.append("")
        lines.append("<b>All day</b>")
        for e in allday:
            lines.append(f"  {esc(shorten(e['title'], 40))}")

    if stale_min > STALE_AFTER_MIN:
        lines.append("")
        lines.append(f"<b>⚠ agenda is {stale_min}m old</b> — calendar-agenda.service may be failing")

    emit(text, "\n".join(lines), cls)


if __name__ == "__main__":
    main()
