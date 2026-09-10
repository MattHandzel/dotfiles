#!/usr/bin/env python3
"""Synthetic full-screen scene generator with exact ground-truth region annotations.

Fixtures for evaluating `kbshot` region detection.  Every ground-truth box is
*derived* from the draw helper that painted the element -- no coordinate literal
ever enters the annotation list.

Usage:
    gen_scenes.py            # generate scenes/ + ground_truth.json + index.md
    gen_scenes.py --verify   # validate ground_truth.json and emit verify-*.png
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont


def _find_font(*names: str) -> str:
    """Resolve a font file by fontconfig rather than hardcoding a store path."""
    for name in names:
        try:
            out = subprocess.run(
                ["fc-match", "-f", "%{file}", name],
                capture_output=True, text=True, check=True,
            ).stdout.strip()
        except (OSError, subprocess.CalledProcessError):
            continue
        if out and Path(out).is_file():
            return out
    raise SystemExit(f"could not resolve a font for {names!r}; is fontconfig installed?")

def _font_dir() -> str:
    """Directory holding the DejaVu family, resolved at runtime."""
    return str(Path(_find_font("DejaVu Sans", "sans-serif")).parent)


HERE = Path(__file__).resolve().parent
OUT = HERE / "scenes"

W, H = 2880, 1800

FDIR = Path(_font_dir())
FONT_FILES = {
    "sans": "DejaVuSans.ttf",
    "sans-bold": "DejaVuSans-Bold.ttf",
    "sans-oblique": "DejaVuSans-Oblique.ttf",
    "serif": "DejaVuSerif.ttf",
    "serif-bold": "DejaVuSerif-Bold.ttf",
    "serif-italic": "DejaVuSerif-Italic.ttf",
    "mono": "DejaVuSansMono.ttf",
    "mono-bold": "DejaVuSansMono-Bold.ttf",
}

_font_cache: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}


def F(name: str, size: int) -> ImageFont.FreeTypeFont:
    key = (name, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(str(FDIR / FONT_FILES[name]), size)
    return _font_cache[key]


RNG = np.random.default_rng(20260729)

# ---------------------------------------------------------------- text corpus

SENTENCES = [
    "The deploy went out at four in the afternoon and nobody noticed anything unusual until the next morning.",
    "I spent most of yesterday reading through the old migration scripts, and half of them reference tables that no longer exist.",
    "There is a much simpler version of this feature that we could ship this week if we drop the offline mode.",
    "Rain moved in from the west just as the last of the equipment was being carried inside.",
    "She argued that the measurement itself was fine and the problem lived entirely in how we aggregated it afterwards.",
    "Every cache we added made the median faster and the tail dramatically worse.",
    "The building was finished in 1927 and has been renovated three times since, each time badly.",
    "He kept a notebook of every question he could not answer, which turned out to be more useful than the answers.",
    "Our retention numbers look flat until you split them by signup channel, and then two of the channels are clearly broken.",
    "Nothing about the interface suggested that the second click would be permanent.",
    "The library is small, well tested, and completely undocumented outside of its own source comments.",
    "After the third outage we finally wrote down what the on-call rotation was actually supposed to do.",
    "It takes about eleven minutes to walk from the station to the office if the lights cooperate.",
    "Most of the cost is not in the model but in everything we do to the data before it reaches the model.",
    "The proposal is reasonable, but it assumes a level of coordination between the two teams that has never once existed.",
    "Snow had drifted against the north wall high enough to bury the lower window entirely.",
    "We measured latency at the edge, at the gateway, and inside the handler, and the three numbers disagree by an order of magnitude.",
    "A surprising fraction of support tickets are people asking where the export button went.",
    "The original authors left in 2019 and took the only working mental model of the scheduler with them.",
    "Reading the transcript afterwards, it is obvious that both sides were describing the same problem with different vocabulary.",
    "I would rather have one slow test that catches real regressions than four hundred fast ones that never fail.",
    "The garden had been left alone for two seasons and had reorganised itself accordingly.",
    "Growth stalled the same week we changed the onboarding copy, which may or may not be a coincidence.",
    "There are twelve configuration flags controlling this behaviour and no document explaining which combinations are legal.",
    "He described the whole architecture on a napkin in about ninety seconds and it was more precise than the design doc.",
    "Once the index fit in memory the query planner stopped making bizarre decisions.",
    "The photograph was taken from the far shore, which is why the boats look closer together than they are.",
    "We agreed to revisit the decision in a month, and then quietly built everything else on top of it.",
    "Users do not read error messages, but they do read the first four words of them.",
    "The failure was not in the retry logic; it was in the assumption that retrying was safe.",
    "Two engineers independently discovered the same bug within an hour and filed nearly identical reports.",
    "By the time the meeting ended the original question had been replaced by a much better one.",
    "Cold mornings here smell like woodsmoke and diesel in roughly equal measure.",
    "The dataset is clean in the sense that every field is populated, and dirty in every sense that matters.",
    "If you sort the table by last modified you can see exactly when the team stopped caring about it.",
    "It works locally, which is the least interesting property a system can have.",
    "We are optimising a metric that correlates with the thing we want only during business hours.",
    "The interview process filters heavily for people who are comfortable being watched while thinking.",
    "Three of the six charts on that dashboard have been broken since the schema change in April.",
    "Someone had labelled the cable, which felt like a small miracle.",
    "The refactor touched nine hundred files and changed behaviour in exactly one of them.",
    "Half the value of writing it down is discovering which parts you cannot actually explain.",
    "Traffic doubled overnight because a single popular account linked to the page.",
    "The room was quiet enough that you could hear the fans spin up when the batch job started.",
    "We shipped the smaller version, and after six weeks nobody has asked for the rest of it.",
    "Each additional reviewer made the pull request slower without making it noticeably safer.",
]

SHORT = [
    "Ah, that explains it.",
    "Yep, merged.",
    "Looks good to me.",
    "On it now.",
    "Rolling back, give me a minute.",
    "Nice catch, thanks.",
    "Will pick this up after standup.",
    "Reproduced on staging too.",
]

_sent_i = 0
_short_i = 0


def sentence() -> str:
    global _sent_i
    s = SENTENCES[_sent_i % len(SENTENCES)]
    _sent_i += 1
    return s


def sentences(n: int) -> str:
    return " ".join(sentence() for _ in range(n))


def short() -> str:
    global _short_i
    s = SHORT[_short_i % len(SHORT)]
    _short_i += 1
    return s


# ---------------------------------------------------------------- geometry

Box = tuple[float, float, float, float]  # x0, y0, x1, y1


def union(boxes) -> Box:
    bs = [b for b in boxes if b is not None]
    if not bs:
        raise ValueError("union of nothing")
    return (
        min(b[0] for b in bs),
        min(b[1] for b in bs),
        max(b[2] for b in bs),
        max(b[3] for b in bs),
    )


# ---------------------------------------------------------------- themes

DARK = dict(
    name="dark",
    bg=(27, 29, 33),
    panel=(34, 37, 42),
    panel2=(41, 45, 51),
    panel3=(50, 55, 62),
    sep=(52, 56, 64),
    text=(230, 232, 236),
    dim=(151, 157, 166),
    faint=(112, 118, 127),
    accent=(80, 142, 222),
    good=(92, 178, 122),
    warn=(214, 160, 70),
    bad=(216, 100, 94),
    code_bg=(23, 25, 29),
    kw=(198, 120, 221),
    strc=(152, 195, 121),
    com=(108, 117, 128),
    num=(209, 154, 102),
    fnc=(97, 175, 239),
    page=(240, 235, 224),
    page_ink=(38, 34, 30),
    surround=(16, 18, 22),
    stripe=(40, 44, 51),
)

LIGHT = dict(
    name="light",
    bg=(251, 251, 253),
    panel=(255, 255, 255),
    panel2=(241, 242, 245),
    panel3=(231, 233, 238),
    sep=(221, 224, 230),
    text=(29, 32, 38),
    dim=(107, 114, 128),
    faint=(148, 154, 163),
    accent=(36, 102, 196),
    good=(28, 128, 72),
    warn=(166, 110, 20),
    bad=(188, 58, 50),
    code_bg=(245, 246, 250),
    kw=(166, 38, 164),
    strc=(70, 116, 52),
    com=(150, 154, 162),
    num=(154, 88, 20),
    fnc=(32, 100, 190),
    page=(252, 248, 240),
    page_ink=(42, 38, 34),
    surround=(74, 77, 85),
    stripe=(240, 242, 247),
)

AVATAR_COLORS = [
    (196, 88, 96),
    (86, 140, 196),
    (94, 158, 110),
    (176, 132, 78),
    (140, 110, 190),
    (76, 156, 168),
    (198, 118, 74),
]


# ---------------------------------------------------------------- scene


class Scene:
    def __init__(self, name: str, theme: dict):
        self.name = name
        self.th = theme
        self.img = Image.new("RGB", (W, H), theme["bg"])
        self.d = ImageDraw.Draw(self.img)
        self.records: list[dict] = []
        self._ids: set[str] = set()

    def redraw(self) -> None:
        self.d = ImageDraw.Draw(self.img)

    def mark(self, eid: str, kind: str, box: Box, priority: str) -> Box:
        assert kind in KINDS, kind
        assert priority in ("primary", "secondary"), priority
        assert eid not in self._ids, f"duplicate id {eid} in {self.name}"
        self._ids.add(eid)
        x0, y0, x1, y1 = box
        assert x1 > x0 and y1 > y0, f"degenerate box for {eid}: {box}"
        self.records.append(
            {
                "scene": f"{self.name}.png",
                "id": eid,
                "kind": kind,
                "bbox": [
                    int(round(x0)),
                    int(round(y0)),
                    int(round(x1 - x0)),
                    int(round(y1 - y0)),
                ],
                "priority": priority,
            }
        )
        return box

    def finish(self) -> None:
        """Add a faint per-channel dither so edges are not perfect step edges."""
        a = np.asarray(self.img).astype(np.int16)
        a += RNG.integers(-2, 3, size=a.shape, dtype=np.int16)
        self.img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
        self.redraw()


KINDS = {
    "message",
    "message-group",
    "paragraph",
    "heading",
    "figure",
    "figure-with-caption",
    "code-block",
    "code-line",
    "table",
    "table-row",
    "table-cell",
    "terminal-command",
    "terminal-output",
    "card",
    "chart",
    "pane",
    "window",
    "button",
    "avatar",
    "quote",
    "column",
    "nested-rect",
    "list-item",
}


# ---------------------------------------------------------------- primitives


def txt(d, xy, s, f, fill, anchor=None) -> Box | None:
    """Draw one run of text; return the tight ink box PIL reports for it."""
    if not s or not s.strip():
        return None
    d.text(xy, s, font=f, fill=fill, anchor=anchor)
    return d.textbbox(xy, s, font=f, anchor=anchor)


def wrap(d, text: str, f, maxw: float) -> list[str]:
    words = text.split()
    lines: list[str] = []
    cur = ""
    for w in words:
        cand = w if not cur else f"{cur} {w}"
        if d.textlength(cand, font=f) <= maxw or not cur:
            cur = cand
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def para(d, x, y, lines, f, fill, lh) -> tuple[Box, float]:
    boxes = []
    for i, line in enumerate(lines):
        b = txt(d, (x, y + i * lh), line, f, fill)
        if b:
            boxes.append(b)
    return union(boxes), y + len(lines) * lh


def justified(d, x, y, words, f, fill, maxw) -> Box:
    if len(words) < 2:
        return txt(d, (x, y), " ".join(words), f, fill)
    widths = [d.textlength(w, font=f) for w in words]
    gap = (maxw - sum(widths)) / (len(words) - 1)
    gap = max(gap, d.textlength(" ", font=f) * 0.6)
    boxes = []
    cx = x
    for w, wd in zip(words, widths):
        b = txt(d, (cx, y), w, f, fill)
        if b:
            boxes.append(b)
        cx += wd + gap
    return union(boxes)


def justify_paragraph(d, x, y, text, f, fill, maxw, lh) -> tuple[Box, float]:
    lines = wrap(d, text, f, maxw)
    boxes = []
    for i, line in enumerate(lines):
        words = line.split()
        last = i == len(lines) - 1
        yy = y + i * lh
        b = (
            txt(d, (x, yy), line, f, fill)
            if last
            else justified(d, x, yy, words, f, fill, maxw)
        )
        if b:
            boxes.append(b)
    return union(boxes), y + len(lines) * lh


def rrect(d, box: Box, radius, fill=None, outline=None, width=1) -> Box:
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)
    return box


def rect(d, box: Box, fill=None, outline=None, width=1) -> Box:
    d.rectangle(box, fill=fill, outline=outline, width=width)
    return box


def circle(d, cx, cy, r, fill, outline=None) -> Box:
    box = (cx - r, cy - r, cx + r, cy + r)
    d.ellipse(box, fill=fill, outline=outline)
    return box


def avatar(d, cx, cy, r, idx, initials, th) -> Box:
    col = AVATAR_COLORS[idx % len(AVATAR_COLORS)]
    b = circle(d, cx, cy, r, col)
    txt(d, (cx, cy + 1), initials, F("sans-bold", int(r * 0.9)), (250, 250, 252), "mm")
    return b


def hairline(d, x0, y, x1, col) -> Box:
    d.line([(x0, y), (x1, y)], fill=col, width=1)
    return (x0, y, x1, y + 1)


# ================================================================ 1. slack


def build_slack(sc: Scene) -> None:
    th, d = sc.th, sc.d
    side_w = 600

    # ---- sidebar
    sb = rect(d, (0, 0, side_w, H), fill=th["panel2"])
    hairline(d, side_w, 0, side_w, th["sep"])
    txt(d, (44, 46), "Northbridge Labs", F("sans-bold", 38), th["text"])
    txt(d, (44, 100), "matth", F("sans", 26), th["dim"])
    hairline(d, 32, 156, side_w - 32, th["sep"])
    txt(d, (44, 186), "Channels", F("sans-bold", 24), th["faint"])
    channels = [
        "# general",
        "# engineering",
        "# design-review",
        "# incidents",
        "# deploys",
        "# hiring",
        "# docs",
        "# on-call",
        "# product",
        "# random",
        "# watercooler",
        "# metrics",
    ]
    cy = 234
    for i, ch in enumerate(channels):
        if i == 1:
            rrect(d, (28, cy - 8, side_w - 28, cy + 44), 10, fill=th["panel3"])
            txt(d, (52, cy), ch, F("sans-bold", 30), th["text"])
            rrect(d, (side_w - 100, cy + 4, side_w - 44, cy + 36), 14, fill=th["bad"])
            txt(
                d,
                ((side_w - 72), cy + 20),
                "4",
                F("sans-bold", 22),
                (250, 250, 250),
                "mm",
            )
        else:
            txt(d, (52, cy), ch, F("sans", 30), th["dim"])
        cy += 56
    txt(d, (44, cy + 20), "Direct messages", F("sans-bold", 24), th["faint"])
    cy += 68
    for nm, idx in (("Priya Raman", 1), ("Dan Okafor", 0), ("Mei-Lin Chen", 2)):
        avatar(d, 62, cy + 16, 16, idx, nm[0], th)
        txt(d, (92, cy), nm, F("sans", 28), th["dim"])
        cy += 52
    sc.mark("sidebar", "pane", sb, "secondary")

    # ---- channel header
    txt(d, (656, 44), "# engineering", F("sans-bold", 40), th["text"])
    txt(d, (656, 96), "24 members  ·  Deploys, reviews, incidents",
        F("sans", 26), th["dim"])
    hairline(d, side_w, 148, W, th["sep"])

    body_f = F("sans", 30)
    auth_f = F("sans-bold", 32)
    ts_f = F("sans", 24)
    mono_f = F("mono", 26)
    lh = 44
    ax, tx = 660, 764
    body_w = 1960

    y = 176
    msgs: list[Box] = []
    people = [
        ("Priya Raman", "P", 1),
        ("Dan Okafor", "D", 0),
        ("Mei-Lin Chen", "M", 2),
        ("Tobias Wright", "T", 3),
        ("Rowan Fitzgerald", "R", 4),
        ("Hana Yusuf", "H", 5),
        ("Sam Alvarez", "S", 6),
    ]
    times = ["09:02", "09:07", "09:14", "09:26", "09:31", "09:33", "09:38", "09:51"]

    def header(name, initials, idx, ts, yy):
        ab = avatar(d, ax + 36, yy + 22, 36, idx, initials, th)
        nb = txt(d, (tx, yy), name, auth_f, th["text"])
        tb = txt(d, (tx + d.textlength(name, font=auth_f) + 20, yy + 8), ts, ts_f,
                 th["faint"])
        return ab, union([nb, tb])

    # message 1 -- 2 lines
    nm, ini, idx = people[0]
    ab, hb = header(nm, ini, idx, times[0], y)
    pb, y2 = para(d, tx, y + 42, wrap(d, sentences(1), body_f, body_w)[:2], body_f,
                  th["text"], lh)
    msgs.append(sc.mark("msg-1", "message", union([ab, hb, pb]), "primary"))
    sc.mark("avatar-1", "avatar", ab, "secondary")
    y = y2 + 24

    # message 2 -- short
    nm, ini, idx = people[1]
    ab, hb = header(nm, ini, idx, times[1], y)
    pb, y2 = para(d, tx, y + 42, [short()], body_f, th["text"], lh)
    msgs.append(sc.mark("msg-2", "message", union([ab, hb, pb]), "primary"))
    sc.mark("avatar-2", "avatar", ab, "secondary")
    y = y2 + 24

    # message 3 -- 3 lines
    nm, ini, idx = people[2]
    ab, hb = header(nm, ini, idx, times[2], y)
    pb, y2 = para(d, tx, y + 42, wrap(d, sentences(2), body_f, body_w)[:3], body_f,
                  th["text"], lh)
    msgs.append(sc.mark("msg-3", "message", union([ab, hb, pb]), "primary"))
    sc.mark("avatar-3", "avatar", ab, "secondary")
    y = y2 + 24

    # message 4 -- text + code snippet
    nm, ini, idx = people[3]
    ab, hb = header(nm, ini, idx, times[3], y)
    pb, y2 = para(d, tx, y + 42,
                  wrap(d, "Here is the exact query the planner keeps choosing, "
                          "which explains the tail latency:", body_f, body_w)[:2],
                  body_f, th["text"], lh)
    code = [
        "SELECT r.id, r.status, count(e.id) AS n",
        "  FROM runs r LEFT JOIN events e ON e.run = r.id",
        " WHERE r.created_at > now() - interval '7 days'",
    ]
    cbg_top = y2 + 12
    cb_lines = []
    cy2 = cbg_top + 16
    for line in code:
        b = txt(d, (tx + 22, cy2), line, mono_f, th["strc"])
        cb_lines.append(b)
        cy2 += 38
    cbox = rrect(d, (tx, cbg_top, tx + 1500, cy2 + 6), 10, outline=th["sep"], width=2)
    sc.mark("msg-4-code", "code-block", cbox, "secondary")
    msgs.append(sc.mark("msg-4", "message", union([ab, hb, pb, cbox]), "primary"))
    sc.mark("avatar-4", "avatar", ab, "secondary")
    y = cbox[3] + 24

    # messages 5,6,7 -- consecutive run from one author (avatar only on the first)
    nm, ini, idx = people[4]
    grp: list[Box] = []
    ab, hb = header(nm, ini, idx, times[4], y)
    pb, y2 = para(d, tx, y + 42, wrap(d, sentences(1), body_f, body_w)[:2], body_f,
                  th["text"], lh)
    grp.append(sc.mark("msg-5", "message", union([ab, hb, pb]), "primary"))
    sc.mark("avatar-5", "avatar", ab, "secondary")
    y = y2 + 6
    pb, y2 = para(d, tx, y, [short()], body_f, th["text"], lh)
    grp.append(sc.mark("msg-6", "message", pb, "primary"))
    y = y2 + 6
    pb, y2 = para(d, tx, y, wrap(d, sentences(1), body_f, body_w)[:2], body_f,
                  th["text"], lh)
    grp.append(sc.mark("msg-7", "message", pb, "primary"))
    sc.mark("group-rowan", "message-group", union(grp), "primary")
    msgs.extend(grp)
    y = y2 + 24

    # message 8 -- text + attached image placeholder
    nm, ini, idx = people[5]
    ab, hb = header(nm, ini, idx, times[5], y)
    pb, y2 = para(d, tx, y + 42, ["Screenshot from the incident channel:"], body_f,
                  th["text"], lh)
    ph_top = y2 + 10
    ph = (tx, ph_top, tx + 520, ph_top + 250)
    rrect(d, ph, 12, fill=th["panel2"], outline=th["sep"], width=2)
    d.ellipse((ph[0] + 60, ph[1] + 40, ph[0] + 130, ph[1] + 110), fill=th["accent"])
    d.polygon(
        [
            (ph[0] + 40, ph[3] - 30),
            (ph[0] + 190, ph[1] + 120),
            (ph[0] + 320, ph[3] - 30),
        ],
        fill=th["good"],
    )
    d.polygon(
        [
            (ph[0] + 240, ph[3] - 30),
            (ph[0] + 380, ph[1] + 150),
            (ph[0] + 500, ph[3] - 30),
        ],
        fill=th["panel3"],
    )
    txt(d, (ph[0] + 20, ph[3] - 40), "grafana-latency.png", F("sans", 22), th["dim"])
    sc.mark("msg-8-image", "figure", ph, "secondary")
    msgs.append(sc.mark("msg-8", "message", union([ab, hb, pb, ph]), "primary"))
    sc.mark("avatar-8", "avatar", ab, "secondary")
    y = ph[3] + 24

    # message 9
    nm, ini, idx = people[6]
    ab, hb = header(nm, ini, idx, times[6], y)
    pb, y2 = para(d, tx, y + 42, wrap(d, sentences(2), body_f, body_w)[:3], body_f,
                  th["text"], lh)
    msgs.append(sc.mark("msg-9", "message", union([ab, hb, pb]), "primary"))
    sc.mark("avatar-9", "avatar", ab, "secondary")
    y = y2

    assert y < H - 40, f"slack overflow: {y}"
    sc.mark("message-list", "pane", union(msgs), "primary")


# ================================================================ 2. article


def build_article(sc: Scene) -> None:
    th, d = sc.th, sc.d
    x0, x1 = 690, 2190
    cw = x1 - x0
    parts: list[Box] = []

    body_f = F("sans", 30)
    lh = 44
    y = 150

    hb = txt(d, (x0, y), "What the cache actually taught us", F("sans-bold", 66),
             th["text"])
    parts.append(sc.mark("headline", "heading", hb, "primary"))
    y = hb[3] + 26

    bb = txt(d, (x0, y), "By Rowan Fitzgerald  ·  July 24, 2026  ·  9 min read",
             F("sans", 26), th["dim"])
    parts.append(bb)
    y = bb[3] + 40

    for i in range(2):
        pb, y = para(d, x0, y, wrap(d, sentences(3), body_f, cw), body_f, th["text"], lh)
        parts.append(sc.mark(f"para-{i+1}", "paragraph", pb, "primary"))
        y += 26

    sb = txt(d, (x0, y), "Measuring the wrong tail", F("sans-bold", 44), th["text"])
    parts.append(sc.mark("subheading", "heading", sb, "primary"))
    y = sb[3] + 26

    pb, y = para(d, x0, y, wrap(d, sentences(2), body_f, cw), body_f, th["text"], lh)
    parts.append(sc.mark("para-3", "paragraph", pb, "primary"))
    y += 30

    # blockquote: accent bar + italic serif text
    q_f = F("serif-italic", 34)
    qlines = wrap(d, "Every cache we added made the median faster and the tail "
                     "dramatically worse.", q_f, cw - 60)
    qb, y = para(d, x0 + 44, y + 6, qlines, q_f, th["text"], 52)
    barb = rect(d, (x0, qb[1] - 8, x0 + 6, qb[3] + 8), fill=th["accent"])
    parts.append(sc.mark("pullquote", "quote", union([qb, barb]), "primary"))
    y += 34

    pb, y = para(d, x0, y, wrap(d, sentences(3), body_f, cw), body_f, th["text"], lh)
    parts.append(sc.mark("para-4", "paragraph", pb, "primary"))
    y += 30

    # figure: line chart with axes
    fx0, fy0 = x0, y
    fx1, fy1 = x0 + cw, y + 340
    frame = rrect(d, (fx0, fy0, fx1, fy1), 8, fill=th["panel2"])
    d.line([(fx0 + 90, fy0 + 40), (fx0 + 90, fy1 - 60)], fill=th["faint"], width=2)
    d.line([(fx0 + 90, fy1 - 60), (fx1 - 50, fy1 - 60)], fill=th["faint"], width=2)
    n = 26
    xs = np.linspace(fx0 + 96, fx1 - 60, n)
    base = np.linspace(0.25, 0.8, n) + 0.13 * np.sin(np.linspace(0, 6.5, n))
    for series, col in ((base, th["accent"]), (base * 0.55 + 0.08, th["good"])):
        ys = fy1 - 64 - series * (fy1 - fy0 - 120)
        d.line([(float(a), float(b)) for a, b in zip(xs, ys)], fill=col, width=4,
               joint="curve")
    for i, lab in enumerate(["0", "40", "80", "120"]):
        txt(d, (fx0 + 80, fy1 - 64 - i * (fy1 - fy0 - 120) / 3), lab, F("sans", 20),
            th["dim"], "rm")
    txt(d, (fx0 + 100, fy0 + 20), "p50 vs p99 request latency (ms)", F("sans-bold", 24),
        th["dim"])
    sc.mark("figure-chart", "figure", frame, "secondary")
    cap = txt(d, (fx0, fy1 + 14),
              "Figure 1. Median latency improved every quarter; the 99th percentile "
              "did not.", F("sans-oblique", 24), th["dim"])
    fwc = sc.mark("figure-1", "figure-with-caption", union([frame, cap]), "primary")
    parts.append(fwc)
    y = fwc[3] + 34

    pb, y = para(d, x0, y, wrap(d, sentences(2), body_f, cw), body_f, th["text"], lh)
    parts.append(sc.mark("para-5", "paragraph", pb, "primary"))

    assert pb[3] < H - 40, f"article overflow: {pb[3]}"
    sc.mark("reading-column", "column", union(parts), "primary")


# ================================================================ 3. book-page


def build_book(sc: Scene) -> None:
    """Photo-of-a-book look: rotated off-white page, soft shadow, dark surround.

    Content is drawn on an unrotated layer; every ground-truth box is recovered
    by rotating that element's own mask with the identical transform and taking
    the axis-aligned bounds of the surviving pixels.
    """
    th = sc.th
    rect(sc.d, (0, 0, W, H), fill=th["surround"])

    PW, PH = 1780, 1500
    ang = 1.7 if th["name"] == "dark" else -1.4

    layer = Image.new("RGBA", (PW, PH), tuple(th["page"]) + (255,))
    ld = ImageDraw.Draw(layer)
    ink = th["page_ink"]
    dim_ink = tuple(min(255, c + 90) for c in ink)

    # paper tint: faint vertical gutter shading
    for i in range(60):
        v = int(10 * math.sin(i / 60 * math.pi))
        ld.line([(PW / 2 - 30 + i, 0), (PW / 2 - 30 + i, PH)],
                fill=tuple(max(0, c - v) for c in th["page"]))

    elems: list[tuple[str, str, str, Box]] = []

    ser = F("serif", 27)
    lh = 43
    mx = 120
    gutter = 90
    colw = (PW - 2 * mx - gutter) / 2

    hb = txt(ld, (mx, 62), "THE MEASUREMENT PROBLEM", F("serif", 22), dim_ink)
    ld.text((PW - mx, 62), "CHAPTER FOUR", font=F("serif", 22), fill=dim_ink,
            anchor="ra")
    hline = ld.textbbox((PW - mx, 62), "CHAPTER FOUR", font=F("serif", 22), anchor="ra")
    ld.line([(mx, 104), (PW - mx, 104)], fill=dim_ink, width=1)

    for ci in range(2):
        cx = mx + ci * (colw + gutter)
        y = 150
        pboxes = []
        for pi in range(4):
            text = sentences(3 if pi else 2)
            indent = 34 if pi else 0
            lines = wrap(ld, text, ser, colw)
            # first line indented, remainder full measure
            boxes = []
            for li, line in enumerate(lines):
                xx = cx + (indent if li == 0 else 0)
                mw = colw - (indent if li == 0 else 0)
                yy = y + li * lh
                words = line.split()
                if li == len(lines) - 1:
                    b = txt(ld, (xx, yy), line, ser, ink)
                else:
                    b = justified(ld, xx, yy, words, ser, ink, mw)
                if b:
                    boxes.append(b)
            pb = union(boxes)
            y += len(lines) * lh + 16
            elems.append((f"col{ci+1}-para-{pi+1}", "paragraph", "primary", pb))
            pboxes.append(pb)
            if y > PH - 170:
                break
        elems.append((f"column-{ci+1}", "column", "primary", union(pboxes)))

    pn = txt(ld, (PW / 2, PH - 78), "97", F("serif", 24), dim_ink, "ma")
    elems.append(("page", "figure", "primary", (0, 0, PW - 1, PH - 1)))

    # rotate page + shadow
    rl = layer.rotate(ang, resample=Image.BICUBIC, expand=True)
    ox = (W - rl.width) // 2
    oy = (H - rl.height) // 2

    alpha = rl.split()[3]
    shadow = Image.new("L", (W, H), 0)
    shadow.paste(alpha, (ox + 8, oy + 18))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    shadow = shadow.point(lambda v: int(v * 0.62))
    sc.img = Image.composite(Image.new("RGB", (W, H), (0, 0, 0)), sc.img, shadow)
    sc.img.paste(rl.convert("RGB"), (ox, oy), alpha)
    sc.redraw()

    for eid, kind, pri, local in elems:
        m = Image.new("L", (PW, PH), 0)
        ImageDraw.Draw(m).rectangle(local, fill=255)
        rm = np.asarray(m.rotate(ang, resample=Image.NEAREST, expand=True))
        ys, xs = np.nonzero(rm)
        sc.mark(
            eid, kind,
            (xs.min() + ox, ys.min() + oy, xs.max() + 1 + ox, ys.max() + 1 + oy),
            pri,
        )


# ================================================================ 4. code-editor

PY_CODE = [
    # (indent, [(text, colour-key)])
    (0, [("# ---------------------------------------------------------------", "com")]),
    (0, [("# Retry policy.  The 2026-03 incident was not a retry bug: the", "com")]),
    (0, [("# retries were correct and the operation was never idempotent.", "com")]),
    (0, [("# Keep the jitter -- synchronised clients rebuilt the thundering", "com")]),
    (0, [("# herd every time we removed it.", "com")]),
    (0, [("# ---------------------------------------------------------------", "com")]),
    (0, []),
    (0, [("def", "kw"), (" backoff", "fnc"), ("(attempt, base=", "txt"),
         ("0.25", "num"), (", cap=", "txt"), ("30.0", "num"), ("):", "txt")]),
    (1, [('"""Exponential delay with full jitter."""', "strc")]),
    (1, [("span", "txt"), (" = ", "txt"), ("min", "fnc"), ("(cap, base * ", "txt"),
         ("2", "num"), (" ** attempt)", "txt")]),
    (1, [("return", "kw"), (" random.uniform(", "txt"), ("0.0", "num"),
         (", span)", "txt")]),
    (0, []),
    (0, []),
    (0, [("def", "kw"), (" load_manifest", "fnc"), ("(path: Path) -> ", "txt"),
         ("dict", "fnc"), (":", "txt")]),
    (1, [("raw", "txt"), (" = path.read_text(encoding=", "txt"),
         ('"utf-8"', "strc"), (")", "txt")]),
    (1, [("try", "kw"), (":", "txt")]),
    (2, [("doc", "txt"), (" = json.loads(raw)", "txt")]),
    (1, [("except", "kw"), (" json.JSONDecodeError ", "txt"), ("as", "kw"),
         (" exc:", "txt")]),
    (2, [("raise", "kw"), (" ManifestError(", "txt"),
         ('f"bad manifest {path}: {exc}"', "strc"), (") ", "txt"), ("from", "kw"),
         (" exc", "txt")]),
    (1, [("if", "kw"), (" doc.get(", "txt"), ('"version"', "strc"), (") != ", "txt"),
         ("2", "num"), (":", "txt")]),
    (2, [("raise", "kw"), (" ManifestError(", "txt"),
         ('"only version 2 is supported"', "strc"), (")", "txt")]),
    (1, [("return", "kw"), (" doc", "txt")]),
    (0, []),
    (0, []),
    (0, [("async def", "kw"), (" drain", "fnc"), ("(queue, handler, workers=", "txt"),
         ("4", "num"), ("):", "txt")]),
    (1, [("sem", "txt"), (" = asyncio.Semaphore(workers)", "txt")]),
    (0, []),
    (1, [("async def", "kw"), (" one", "fnc"), ("(item):", "txt")]),
    (2, [("async with", "kw"), (" sem:", "txt")]),
    (3, [("for", "kw"), (" attempt ", "txt"), ("in", "kw"), (" range(", "txt"),
         ("5", "num"), ("):", "txt")]),
    (4, [("try", "kw"), (":", "txt")]),
    (5, [("return await", "kw"), (" handler(item)", "txt")]),
    (4, [("except", "kw"), (" TransientError:", "txt")]),
    (5, [("await", "kw"), (" asyncio.sleep(backoff(attempt))", "txt")]),
    (3, [("raise", "kw"), (" GaveUp(item.id)", "txt")]),
    (0, []),
    (1, [("await", "kw"), (" asyncio.gather(*(one(i) ", "txt"), ("for", "kw"),
         (" i ", "txt"), ("in", "kw"), (" queue))", "txt")]),
]


def build_editor(sc: Scene) -> None:
    th, d = sc.th, sc.d
    rect(d, (0, 0, W, H), fill=tuple(max(0, c - 8) for c in th["bg"]))

    wx0, wy0, wx1, wy1 = 36, 36, W - 36, H - 36
    win = rrect(d, (wx0, wy0, wx1, wy1), 18, fill=th["panel"])

    # tab bar
    tb_h = 74
    rect(d, (wx0, wy0 + 10, wx1, wy0 + tb_h), fill=th["panel2"])
    tabs = ["worker.py", "manifest.py", "test_drain.py"]
    tx = wx0 + 26
    for i, t in enumerate(tabs):
        tw = d.textlength(t, font=F("sans", 26)) + 76
        if i == 0:
            rrect(d, (tx, wy0 + 14, tx + tw, wy0 + tb_h + 4), 8, fill=th["code_bg"])
            txt(d, (tx + 24, wy0 + 30), t, F("sans", 26), th["text"])
            txt(d, (tx + tw - 34, wy0 + 30), "×", F("sans", 26), th["dim"])
        else:
            txt(d, (tx + 24, wy0 + 30), t, F("sans", 26), th["dim"])
        tx += tw
    hairline(d, wx0, wy0 + tb_h, wx1, th["sep"])

    # code surface
    code_top = wy0 + tb_h + 1
    mini_w = 210
    mini_x0 = wx1 - mini_w - 14
    rect(d, (wx0, code_top, mini_x0, wy1), fill=th["code_bg"])
    gut_w = 118
    rect(d, (wx0, code_top, wx0 + gut_w, wy1), fill=th["panel"])
    hairline(d, wx0 + gut_w, code_top, wx0 + gut_w, th["sep"])

    mono = F("mono", 28)
    mono_i = F("mono", 23)
    lh = 41
    ind = d.textlength("    ", font=mono)
    cx0 = wx0 + gut_w + 40
    y = code_top + 26

    colmap = {"com": th["com"], "kw": th["kw"], "strc": th["strc"],
              "num": th["num"], "fnc": th["fnc"], "txt": th["text"]}

    line_boxes: list[Box | None] = []
    for i, (indent, segs) in enumerate(PY_CODE):
        txt(d, (wx0 + gut_w - 24, y + 3), str(i + 1), mono_i, th["faint"], "ra")
        cx = cx0 + indent * ind
        boxes = []
        for s, key in segs:
            b = txt(d, (cx, y), s, mono, colmap[key])
            if b:
                boxes.append(b)
            cx += d.textlength(s, font=mono)
        line_boxes.append(union(boxes) if boxes else None)
        y += lh
    assert y < wy1 - 10, f"editor overflow {y}"

    # minimap: one tiny bar per line, width proportional to line length
    rect(d, (mini_x0, code_top, wx1, wy1), fill=th["panel2"])
    my = code_top + 22
    for indent, segs in PY_CODE:
        length = sum(len(s) for s, _ in segs)
        if length:
            key = segs[0][1]
            bw = min(mini_w - 40, 3 + length * 2.4)
            d.rectangle(
                (mini_x0 + 16 + indent * 6, my, mini_x0 + 16 + indent * 6 + bw, my + 5),
                fill=colmap[key],
            )
        my += 9
    rect(d, (mini_x0 + 8, code_top + 14, wx1 - 8, code_top + 14 + 30 * 9),
         outline=th["panel3"], width=2)

    def blk(lo, hi):
        return union([b for b in line_boxes[lo:hi] if b])

    sc.mark("comment-block", "code-block", blk(0, 6), "primary")
    sc.mark("fn-backoff", "code-block", blk(7, 11), "primary")
    sc.mark("fn-load-manifest", "code-block", blk(13, 22), "primary")
    sc.mark("fn-drain", "code-block", blk(24, len(PY_CODE)), "primary")
    for n in (9, 18, 20, 30):
        sc.mark(f"code-line-{n+1}", "code-line", line_boxes[n], "secondary")
    sc.mark("editor", "pane", win, "primary")


# ================================================================ 5. terminal


def build_terminal(sc: Scene) -> None:
    th, d = sc.th, sc.d
    rect(d, (0, 0, W, H), fill=tuple(max(0, c - 8) for c in th["bg"]))
    wx0, wy0, wx1, wy1 = 60, 60, W - 60, H - 60
    win = rrect(d, (wx0, wy0, wx1, wy1), 16, fill=th["code_bg"])
    rect(d, (wx0, wy0 + 8, wx1, wy0 + 62), fill=th["panel2"])
    for i, col in enumerate([(216, 100, 94), (214, 170, 70), (92, 178, 122)]):
        circle(d, wx0 + 34 + i * 32, wy0 + 36, 11, col)
    txt(d, ((wx0 + wx1) / 2, wy0 + 36), "matth@laptop: ~/projects/ingest",
        F("sans", 26), th["dim"], "mm")
    hairline(d, wx0, wy0 + 62, wx1, th["sep"])

    mono = F("mono", 28)
    lh = 40
    x = wx0 + 34
    y = wy0 + 92

    def prompt(cmd) -> Box:
        nonlocal y
        boxes = []
        cx = x
        for s, col in (("matth@laptop", th["good"]), (":", th["dim"]),
                       ("~/projects/ingest", th["accent"]), ("$ ", th["dim"]),
                       (cmd, th["text"])):
            b = txt(d, (cx, y), s, mono, col)
            if b:
                boxes.append(b)
            cx += d.textlength(s, font=mono)
        y += lh
        return union(boxes)

    def out(lines, col=None) -> Box:
        nonlocal y
        boxes = []
        for line in lines:
            b = txt(d, (x, y), line, mono, col or th["dim"])
            if b:
                boxes.append(b)
            y += lh
        return union(boxes)

    cycles = []

    c = prompt("git status --short")
    o = out([" M ingest/pipeline.py",
             " M ingest/manifest.py",
             "?? scratch/replay.log"])
    cycles.append(("git-status", c, o))
    y += 14

    c = prompt("just check")
    o = out(["   Compiling ingest v0.11.3 (/home/matth/projects/ingest)",
             "    Finished dev [unoptimized + debuginfo] in 14.82s"], th["good"])
    cycles.append(("just-check", c, o))
    y += 14

    c = prompt("ingest stats --by-source --since 7d")
    hdr = out(["source            events    bytes     p50     p99   errors"],
              th["text"])
    tbl = out([
        "kafka.orders    4,182,004   19.4 GB    3ms    41ms       12",
        "kafka.returns     418,220    2.1 GB    4ms    58ms        0",
        "webhook.stripe     92,881    412 MB    9ms   220ms       74",
        "s3.nightly      1,004,556   88.2 GB   11ms   190ms        3",
        "sftp.partner       12,004     41 MB   26ms   980ms      118",
        "--------------------------------------------------------------",
        "total           5,709,665  110.1 GB    4ms    96ms      207",
    ])
    cycles.append(("ingest-stats", c, union([hdr, tbl])))
    sc.mark("stats-table", "table", union([hdr, tbl]), "secondary")
    y += 14

    c = prompt("ingest replay --source sftp.partner --dry-run")
    o1 = out(["reading manifest from s3://ingest-manifests/2026-07-28.json",
              "resolved 118 failed batches"])
    o2 = out(["error: manifest version 3 is not supported (expected 2)",
              "  at ingest/manifest.py:47 in load_manifest",
              "hint: run `ingest manifest migrate --to 2` first"], th["bad"])
    cycles.append(("ingest-replay", c, union([o1, o2])))
    y += 14

    c = prompt("ingest manifest migrate --to 2 && echo ok")
    o = out(["rewrote 118 batch records", "ok"], th["good"])
    cycles.append(("manifest-migrate", c, o))

    assert y < wy1 - 20, f"terminal overflow {y}"

    for name, cbox, obox in cycles:
        sc.mark(f"cmd-{name}", "terminal-command", cbox, "secondary")
        sc.mark(f"cycle-{name}", "terminal-output", union([cbox, obox]), "primary")
    sc.mark("terminal", "pane", win, "primary")


# ================================================================ 6. table

TABLE_ROWS = [
    ("Northeast / Boston", "4,182", "$1,204,880", "+8.4%", "31.2%", "P. Raman"),
    ("Northeast / NYC", "9,915", "$3,411,204", "+12.1%", "28.7%", "D. Okafor"),
    ("Mid-Atlantic / DC", "2,204", "$688,110", "-2.6%", "33.8%", "M. Chen"),
    ("Southeast / Atlanta", "5,470", "$1,509,662", "+4.9%", "29.4%", "T. Wright"),
    ("Southeast / Miami", "3,118", "$902,455", "+1.2%", "26.1%", "T. Wright"),
    ("Midwest / Chicago", "7,662", "$2,240,918", "+6.8%", "30.5%", "R. Fitzgerald"),
    ("Midwest / Minneapolis", "1,880", "$540,221", "-5.1%", "24.9%", "R. Fitzgerald"),
    ("Mountain / Denver", "2,441", "$710,004", "+9.7%", "32.6%", "H. Yusuf"),
    ("Southwest / Phoenix", "3,904", "$1,088,340", "+3.3%", "27.8%", "H. Yusuf"),
    ("Pacific / Seattle", "6,208", "$1,914,772", "+15.4%", "35.1%", "S. Alvarez"),
    ("Pacific / Bay Area", "11,406", "$4,662,118", "+18.9%", "36.4%", "S. Alvarez"),
    ("Pacific / San Diego", "2,712", "$774,509", "-0.8%", "25.3%", "P. Raman"),
]
TABLE_TOTAL = ("Total (12 regions)", "61,122", "$19,747,199", "+7.6%", "30.1%", "--")


def build_table(sc: Scene) -> None:
    th, d = sc.th, sc.d
    tx0, tx1 = 190, 2690
    widths = [700, 340, 420, 300, 300, 440]
    assert sum(widths) == tx1 - tx0
    heads = ["Region / Metro", "Units", "Revenue", "Growth", "Margin", "Owner"]
    aligns = ["l", "r", "r", "r", "r", "l"]

    txt(d, (tx0, 90), "Q3 2026 regional performance", F("sans-bold", 46), th["text"])
    txt(d, (tx0, 150), "Sheet 1 of 4  ·  updated 3 minutes ago  ·  filters: none",
        F("sans", 26), th["dim"])

    hf = F("sans-bold", 28)
    bf = F("sans", 28)
    row_h = 74
    y = 230
    pad = 22

    def cells(vals, f, y0, h, colors):
        boxes = []
        cx = tx0
        for i, (v, wd) in enumerate(zip(vals, widths)):
            if aligns[i] == "l":
                txt(d, (cx + pad, y0 + h / 2), v, f, colors[i], "lm")
            else:
                txt(d, (cx + wd - pad, y0 + h / 2), v, f, colors[i], "rm")
            boxes.append((cx, y0, cx + wd, y0 + h))
            cx += wd
        return boxes

    all_rows: list[Box] = []
    # header row
    hrow = rect(d, (tx0, y, tx1, y + row_h), fill=th["panel3"])
    hcells = cells(heads, hf, y, row_h, [th["text"]] * 6)
    hairline(d, tx0, y + row_h, tx1, th["sep"])
    sc.mark("row-header", "table-row", hrow, "primary")
    all_rows.append(hrow)
    y += row_h

    cell_marks = []
    for ri, row in enumerate(TABLE_ROWS):
        fill = th["stripe"] if ri % 2 else th["panel"]
        rb = rect(d, (tx0, y, tx1, y + row_h), fill=fill)
        cols = [th["text"], th["text"], th["text"],
                th["good"] if row[3].startswith("+") else th["bad"],
                th["dim"], th["dim"]]
        cb = cells(row, bf, y, row_h, cols)
        hairline(d, tx0, y + row_h, tx1, th["sep"])
        sc.mark(f"row-{ri+1}", "table-row", rb, "primary")
        all_rows.append(rb)
        if ri in (0, 3, 7, 10):
            cell_marks.append((ri, 0, cb[0]))
            cell_marks.append((ri, 2, cb[2]))
        y += row_h

    trow = rect(d, (tx0, y, tx1, y + row_h + 6), fill=th["panel3"])
    cells(TABLE_TOTAL, hf, y, row_h + 6, [th["text"]] * 6)
    sc.mark("row-total", "table-row", trow, "primary")
    all_rows.append(trow)
    y += row_h + 6

    for ri, ci, box in cell_marks:
        sc.mark(f"cell-r{ri+1}c{ci+1}", "table-cell", box, "secondary")

    rect(d, union(all_rows), outline=th["sep"], width=2)
    assert y < H - 40, f"table overflow {y}"
    sc.mark("table", "table", union(all_rows), "primary")


# ================================================================ 7. dashboard


def build_dashboard(sc: Scene) -> None:
    th, d = sc.th, sc.d
    txt(d, (100, 64), "Ingest health", F("sans-bold", 46), th["text"])
    txt(d, (100, 122), "Last 24 hours  ·  all sources  ·  auto-refresh 30s",
        F("sans", 26), th["dim"])
    rrect(d, (2500, 66, 2780, 130), 10, fill=th["panel3"], outline=th["sep"], width=2)
    txt(d, (2640, 98), "Export CSV", F("sans", 26), th["text"], "mm")

    m, gap = 100, 40
    top = 190
    cw = (W - 2 * m - 2 * gap) / 3
    ch = (H - top - 90 - gap) / 2

    cards: list[Box] = []
    titles = [
        "Events per minute",
        "Bytes by source",
        "Error budget remaining",
        "p99 latency",
        "Volume share",
        "Backlog pressure",
    ]

    for i in range(6):
        col, row = i % 3, i // 3
        x0 = m + col * (cw + gap)
        y0 = top + row * (ch + gap)
        x1, y1 = x0 + cw, y0 + ch
        cb = rrect(d, (x0, y0, x1, y1), 16, fill=th["panel"], outline=th["sep"],
                   width=2)
        tb = txt(d, (x0 + 34, y0 + 28), titles[i], F("sans-bold", 30), th["text"])
        txt(d, (x0 + 34, y0 + 70), "compared with previous day", F("sans", 22),
            th["dim"])
        px0, py0 = x0 + 40, y0 + 122
        px1, py1 = x1 - 40, y1 - 44
        chart = _dash_chart(d, th, i, px0, py0, px1, py1)
        sc.mark(f"card-{i+1}", "card", cb, "primary")
        sc.mark(f"chart-{i+1}", "chart", chart, "primary")
        cards.append(cb)

    sc.mark("dashboard", "pane", union(cards), "secondary")


def _dash_chart(d, th, i, x0, y0, x1, y1) -> Box:
    """Draw the i-th visual and return the box bounding the marks it painted."""
    boxes: list[Box] = []
    w, h = x1 - x0, y1 - y0
    if i == 0:  # line chart with area
        n = 40
        xs = np.linspace(x0, x1, n)
        v = 0.5 + 0.32 * np.sin(np.linspace(0, 7, n)) + 0.06 * np.sin(
            np.linspace(0, 23, n))
        ys = y1 - v * h
        pts = [(float(a), float(b)) for a, b in zip(xs, ys)]
        d.polygon(pts + [(x1, y1), (x0, y1)], fill=tuple(
            int(c * 0.35 + t * 0.65) for c, t in zip(th["accent"], th["panel"])))
        d.line(pts, fill=th["accent"], width=5, joint="curve")
        boxes.append((x0, min(ys), x1, y1))
    elif i == 1:  # bar chart
        n = 7
        bw = w / n * 0.62
        vals = [0.85, 0.62, 0.44, 0.71, 0.33, 0.55, 0.28]
        labs = ["kaf", "ret", "stp", "s3", "sft", "gcs", "api"]
        for j, v in enumerate(vals):
            bx = x0 + j * (w / n) + (w / n - bw) / 2
            bb = (bx, y1 - 34 - v * (h - 40), bx + bw, y1 - 34)
            d.rounded_rectangle(bb, radius=6, fill=th["accent"] if j != 3
                                else th["good"])
            boxes.append(bb)
            b = txt(d, ((bb[0] + bb[2]) / 2, y1 - 26), labs[j], F("sans", 20),
                    th["dim"], "ma")
            if b:
                boxes.append(b)
    elif i == 2:  # big number + delta
        b = txt(d, (x0, y0 + h * 0.30), "68.4%", F("sans-bold", 132), th["text"])
        boxes.append(b)
        b2 = txt(d, (x0, b[3] + 18), "-11.2 pts vs yesterday", F("sans", 28),
                 th["bad"])
        boxes.append(b2)
        bar = (x0, b2[3] + 26, x1, b2[3] + 44)
        d.rounded_rectangle(bar, radius=9, fill=th["panel3"])
        d.rounded_rectangle((bar[0], bar[1], bar[0] + w * 0.684, bar[3]), radius=9,
                            fill=th["good"])
        boxes.append(bar)
    elif i == 3:  # sparkline row
        n = 60
        xs = np.linspace(x0, x1, n)
        v = 0.45 + 0.3 * np.abs(np.sin(np.linspace(0, 9, n))) + np.linspace(0, .12, n)
        ys = y0 + h * 0.55 - (v - 0.45) * h * 0.9
        pts = [(float(a), float(b)) for a, b in zip(xs, ys)]
        d.line(pts, fill=th["warn"], width=4, joint="curve")
        circle(d, pts[-1][0] - 4, pts[-1][1], 9, th["warn"])
        boxes.append((x0, min(ys) - 9, x1, max(ys) + 9))
        b = txt(d, (x0, y1 - 60), "96 ms  p99", F("sans-bold", 34), th["text"])
        boxes.append(b)
    elif i == 4:  # pie
        r = min(w, h) / 2 - 8
        cx, cy = x0 + r + 10, y0 + h / 2
        pie = (cx - r, cy - r, cx + r, cy + r)
        segs = [(0, 148, th["accent"]), (148, 226, th["good"]),
                (226, 292, th["warn"]), (292, 360, th["bad"])]
        for a0, a1, col in segs:
            d.pieslice(pie, a0 - 90, a1 - 90, fill=col)
        boxes.append(pie)
        ly = y0 + 12
        for lab, col in (("kafka 41%", th["accent"]), ("s3 22%", th["good"]),
                         ("stripe 18%", th["warn"]), ("other 19%", th["bad"])):
            d.rectangle((cx + r + 40, ly + 6, cx + r + 62, ly + 28), fill=col)
            b = txt(d, (cx + r + 76, ly), lab, F("sans", 24), th["dim"])
            boxes.append((cx + r + 40, ly, b[2], max(b[3], ly + 28)))
            ly += 46
    else:  # gauge
        r = min(w / 2, h) - 10
        cx, cy = (x0 + x1) / 2, y1 - 20
        arc = (cx - r, cy - r, cx + r, cy + r)
        d.arc(arc, 180, 360, fill=th["panel3"], width=34)
        d.arc(arc, 180, 180 + 130, fill=th["bad"], width=34)
        boxes.append((cx - r - 17, cy - r - 17, cx + r + 17, cy + 17))
        b = txt(d, (cx, cy - 26), "72%", F("sans-bold", 56), th["text"], "ms")
        boxes.append(b)
    return union(boxes)


# ================================================================ 8. concentric


def build_concentric(sc: Scene) -> None:
    th, d = sc.th, sc.d
    rect(d, (0, 0, W, H), fill=(22, 24, 28))
    sizes = [(1600, 1010), (1040, 650), (620, 392), (262, 166), (82, 62)]
    fills = [(58, 74, 104), (96, 122, 88), (176, 148, 72), (154, 78, 74),
             (226, 226, 232)]
    labels = ["LEVEL 1  outer", "LEVEL 2", "LEVEL 3", "L4", "5"]
    lab_cols = [(226, 232, 240), (232, 240, 226), (30, 28, 22), (250, 236, 232),
                (24, 26, 30)]
    fsizes = [40, 36, 32, 26, 30]
    cx, cy = W / 2, H / 2
    for i, ((rw, rh), fill) in enumerate(zip(sizes, fills)):
        box = (cx - rw / 2, cy - rh / 2, cx + rw / 2, cy + rh / 2)
        d.rectangle(box, fill=fill, outline=(250, 250, 250), width=2)
        if i < 4:
            txt(d, (box[0] + 22, box[1] + 16), labels[i], F("sans-bold", fsizes[i]),
                lab_cols[i])
        else:
            txt(d, ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2 + 1), labels[i],
                F("sans-bold", fsizes[i]), lab_cols[i], "mm")
        sc.mark(f"rect-{i+1}", "nested-rect", box, "primary")


# ================================================================ 9. dense-ui

CONTROL_ROWS = [
    # (label, control-kind, value)
    ("Launch at login", "toggle", True),
    ("Restore previous session", "toggle", True),
    ("Confirm before quitting", "toggle", False),
    ("Check for updates", "select", "Weekly"),
    ("Update channel", "chips", ("Stable", "Beta", "Nightly")),
    ("Telemetry", "toggle", False),
    ("Crash reports", "toggle", True),
    ("Reset onboarding", "button", "Reset"),
    ("Default workspace", "select", "~/projects"),
    ("Recent items kept", "select", "25"),
    ("Clear recent items", "button", "Clear"),
    ("Hardware acceleration", "toggle", True),
    ("Manage extensions", "button", "Manage"),
    ("Font smoothing", "chips", ("Off", "Light", "Full")),
    ("Rebuild search index", "button", "Rebuild"),
    ("Sync over cellular", "toggle", False),
    ("Background refresh", "toggle", True),
    ("Sync interval", "select", "5 min"),
    ("Conflict handling", "chips", ("Ask", "Local", "Remote")),
    ("Sign out of all devices", "button", "Sign out"),
    ("Reveal data folder", "button", "Reveal"),
    ("Trash retention", "select", "30 days"),
    ("Export settings", "button", "Export"),
    ("Import settings", "button", "Import"),
    ("Diagnostics bundle", "button", "Collect"),
    ("Developer mode", "toggle", False),
    ("Verbose logging", "toggle", False),
    ("Log level", "chips", ("warn", "info", "debug")),
    ("Purge local cache", "button", "Purge"),
    ("Restore defaults", "button", "Restore"),
]


def build_dense(sc: Scene) -> None:
    th, d = sc.th, sc.d
    rect(d, (0, 0, W, H), fill=th["bg"])
    txt(d, (120, 60), "Settings", F("sans-bold", 48), th["text"])
    txt(d, (120, 120), "Search settings", F("sans", 26), th["faint"])
    rrect(d, (110, 110, 700, 168), 12, outline=th["sep"], width=2)

    panels = [
        ("General", 120, 200, 1360, 0, 10),
        ("Sync & privacy", 1480, 200, 2760, 10, 20),
        ("Advanced", 120, 1010, 1360, 20, 30),
        ("Appearance", 1480, 1010, 2760, 0, 0),
    ]
    lf = F("sans", 27)
    sf = F("sans", 24)
    btn_marks: list[tuple[str, Box]] = []
    row_h = 66

    for pi, (title, px0, py0, px1, lo, hi) in enumerate(panels):
        rows = CONTROL_ROWS[lo:hi]
        n = len(rows) if rows else 8
        py1 = py0 + 86 + n * row_h + 20
        pb = rrect(d, (px0, py0, px1, py1), 14, fill=th["panel"], outline=th["sep"],
                   width=2)
        txt(d, (px0 + 30, py0 + 26), title, F("sans-bold", 32), th["text"])
        hairline(d, px0 + 1, py0 + 82, px1 - 1, th["sep"])
        y = py0 + 92
        if not rows:  # Appearance panel: theme swatches + sliders
            for j, (lab, val) in enumerate(
                [("Theme", None), ("Accent colour", None), ("Density", None),
                 ("Sidebar width", None), ("Editor font", None), ("UI scale", None),
                 ("Tab size", None), ("Line height", None)]
            ):
                txt(d, (px0 + 30, y + row_h / 2), lab, lf, th["text"], "lm")
                if j < 2:
                    for k in range(5):
                        sx = px1 - 340 + k * 62
                        col = [th["accent"], th["good"], th["warn"], th["bad"],
                               th["panel3"]][k]
                        rrect(d, (sx, y + 16, sx + 46, y + row_h - 12), 8, fill=col,
                              outline=th["sep"], width=2)
                else:
                    trk = (px1 - 340, y + row_h / 2 - 4, px1 - 60, y + row_h / 2 + 4)
                    rrect(d, trk, 4, fill=th["panel3"])
                    frac = 0.3 + 0.12 * j
                    rrect(d, (trk[0], trk[1], trk[0] + (trk[2] - trk[0]) * frac,
                              trk[3]), 4, fill=th["accent"])
                    circle(d, trk[0] + (trk[2] - trk[0]) * frac, y + row_h / 2, 13,
                           th["text"])
                hairline(d, px0 + 30, y + row_h, px1 - 30, th["sep"])
                y += row_h
        for lab, kind, val in rows:
            txt(d, (px0 + 30, y + row_h / 2), lab, lf, th["text"], "lm")
            if kind == "toggle":
                tw, thh = 78, 40
                tb = (px1 - 30 - tw, y + (row_h - thh) / 2, px1 - 30,
                      y + (row_h + thh) / 2)
                rrect(d, tb, thh / 2, fill=th["good"] if val else th["panel3"],
                      outline=th["sep"], width=2)
                kx = tb[2] - thh / 2 if val else tb[0] + thh / 2
                circle(d, kx, (tb[1] + tb[3]) / 2, thh / 2 - 6, (250, 250, 252))
            elif kind == "select":
                bw = 260
                bb = rrect(d, (px1 - 30 - bw, y + 12, px1 - 30, y + row_h - 12), 8,
                           fill=th["panel2"], outline=th["sep"], width=2)
                txt(d, (bb[0] + 18, (bb[1] + bb[3]) / 2), str(val), sf, th["text"],
                    "lm")
                txt(d, (bb[2] - 24, (bb[1] + bb[3]) / 2), "▾", sf, th["dim"],
                    "rm")
            elif kind == "chips":
                cxr = px1 - 30
                for k, chip in enumerate(reversed(val)):
                    cwid = d.textlength(chip, font=sf) + 40
                    on = (len(val) - 1 - k) == 1
                    cb = rrect(d, (cxr - cwid, y + 14, cxr, y + row_h - 14), 16,
                               fill=th["accent"] if on else th["panel2"],
                               outline=th["sep"], width=2)
                    txt(d, ((cb[0] + cb[2]) / 2, (cb[1] + cb[3]) / 2), chip, sf,
                        (250, 250, 252) if on else th["dim"], "mm")
                    cxr -= cwid + 14
            else:  # button
                bwid = d.textlength(str(val), font=sf) + 64
                bb = rrect(d, (px1 - 30 - bwid, y + 12, px1 - 30, y + row_h - 12), 9,
                           fill=th["panel3"], outline=th["sep"], width=2)
                txt(d, ((bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2), str(val), sf,
                    th["text"], "mm")
                btn_marks.append((str(val).lower().replace(" ", "-"), bb))
            hairline(d, px0 + 30, y + row_h, px1 - 30, th["sep"])
            y += row_h
        assert py1 < H - 20, f"dense panel {title} overflow {py1}"
        sc.mark(f"panel-{pi+1}", "card", pb, "primary")

    seen = set()
    for nm, bb in btn_marks:
        if nm in seen:
            continue
        seen.add(nm)
        sc.mark(f"button-{nm}", "button", bb, "secondary")
    assert len(seen) >= 10, f"only {len(seen)} buttons"


# ================================================================ 10. photo-heavy


def build_photo(sc: Scene) -> None:
    th, d = sc.th, sc.d
    bar_h = 78

    # toolbar
    tb = rect(d, (0, 0, W, bar_h), fill=th["panel2"])
    hairline(d, 0, bar_h, W, th["sep"])
    txt(d, (28, bar_h / 2), "‹", F("sans", 34), th["dim"], "lm")
    txt(d, (72, bar_h / 2), "ridgeline-dusk-2026.jpg", F("sans", 26), th["text"], "lm")
    txt(d, (W / 2, bar_h / 2), "4 of 218", F("sans", 24), th["dim"], "mm")
    bx = W - 30
    for lab in ("Share", "Edit", "Info"):
        bwid = d.textlength(lab, font=F("sans", 24)) + 48
        rrect(d, (bx - bwid, 16, bx, bar_h - 16), 8, fill=th["panel3"],
              outline=th["sep"], width=1)
        txt(d, (bx - bwid / 2, bar_h / 2), lab, F("sans", 24), th["text"], "mm")
        bx -= bwid + 16
    sc.mark("toolbar", "pane", tb, "secondary")

    # the photo: synthetic landscape, no text
    iy0 = bar_h + 1
    ih = H - iy0
    grad = np.zeros((ih, W, 3), dtype=np.float64)
    topc = np.array([46, 58, 104]) if th["name"] == "dark" else np.array([120, 158, 210])
    midc = np.array([214, 128, 96]) if th["name"] == "dark" else np.array([242, 200, 168])
    botc = np.array([28, 30, 44]) if th["name"] == "dark" else np.array([78, 92, 110])
    t = np.linspace(0, 1, ih)[:, None]
    sky = np.where(t < 0.62,
                   topc + (midc - topc) * (t / 0.62),
                   midc + (botc - midc) * ((t - 0.62) / 0.38))
    grad[:] = sky[:, None, :]
    photo = Image.fromarray(np.clip(grad, 0, 255).astype(np.uint8))
    pd = ImageDraw.Draw(photo)

    # sun + glow
    sun_y = int(ih * 0.52)
    for r, a in ((360, 18), (250, 26), (160, 40), (96, 90)):
        ov = Image.new("RGBA", photo.size, (0, 0, 0, 0))
        ImageDraw.Draw(ov).ellipse((1720 - r, sun_y - r, 1720 + r, sun_y + r),
                                   fill=(255, 226, 178, a))
        photo = Image.alpha_composite(photo.convert("RGBA"), ov).convert("RGB")
        pd = ImageDraw.Draw(photo)

    # ridgelines, far to near
    ridges = [
        (0.60, (74, 84, 122), 210),
        (0.68, (52, 60, 92), 260),
        (0.76, (34, 40, 64), 300),
    ]
    for frac, col, amp in ridges:
        base = ih * frac
        pts = []
        xs = np.arange(0, W + 1, 20)
        ph = RNG.uniform(0, 6)
        for x in xs:
            yy = base - amp * (
                0.55 * math.sin(x / 620 + ph) + 0.3 * math.sin(x / 210 + ph * 2)
                + 0.15 * math.sin(x / 90)
            )
            pts.append((float(x), float(yy)))
        pd.polygon(pts + [(W, ih), (0, ih)], fill=col)

    # water with reflection band
    wl = int(ih * 0.80)
    pd.rectangle((0, wl, W, ih), fill=(30, 38, 58) if th["name"] == "dark"
                 else (86, 108, 132))
    for i in range(46):
        yy = wl + 8 + i * ((ih - wl) / 46)
        wdt = 40 + RNG.integers(0, 260)
        xx = 1720 - wdt / 2 + RNG.integers(-90, 90)
        pd.line([(xx, yy), (xx + wdt, yy)],
                fill=(226, 186, 150) if i % 2 else (198, 160, 132), width=3)

    # birds
    for bxp, byp, s in ((900, 0.24, 26), (980, 0.20, 18), (1060, 0.27, 22),
                        (2200, 0.18, 20)):
        yy = ih * byp
        pd.arc((bxp - s, yy - s / 2, bxp, yy + s / 2), 200, 340, fill=(30, 30, 38),
               width=3)
        pd.arc((bxp, yy - s / 2, bxp + s, yy + s / 2), 200, 340, fill=(30, 30, 38),
               width=3)

    photo = photo.filter(ImageFilter.GaussianBlur(0.6))
    sc.img.paste(photo, (0, iy0))
    sc.redraw()
    sc.mark("photo", "figure", (0, iy0, W, H), "primary")


# ================================================================ driver

BUILDERS = {
    "slack": build_slack,
    "article": build_article,
    "book-page": build_book,
    "code-editor": build_editor,
    "terminal": build_terminal,
    "table": build_table,
    "dashboard": build_dashboard,
    "dense-ui": build_dense,
    "photo-heavy": build_photo,
}
SINGLE = {"concentric": build_concentric}


def generate() -> list[dict]:
    global _sent_i, _short_i
    OUT.mkdir(parents=True, exist_ok=True)
    records: list[dict] = []
    rows: list[tuple] = []

    jobs = [(f"{n}-{th['name']}", b, th)
            for n, b in BUILDERS.items() for th in (DARK, LIGHT)]
    jobs += [(n, b, DARK) for n, b in SINGLE.items()]

    for name, builder, theme in jobs:
        _sent_i, _short_i = 0, 0  # same copy in both variants of a scene
        sc = Scene(name, theme)
        builder(sc)
        sc.finish()
        sc.img.save(OUT / f"{name}.png")
        records.extend(sc.records)
        kinds: dict[str, int] = {}
        for r in sc.records:
            kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1
        rows.append((
            f"{name}.png",
            theme["name"] if name not in SINGLE else "single",
            kinds,
            sum(1 for r in sc.records if r["priority"] == "primary"),
            sum(1 for r in sc.records if r["priority"] == "secondary"),
        ))
        print(f"wrote {name}.png  ({len(sc.records)} targets)")

    (OUT / "ground_truth.json").write_text(json.dumps(records, indent=1) + "\n")

    lines = [
        "# kbshot eval scenes",
        "",
        f"{len(rows)} images, {W}x{H} each. {len(records)} ground-truth targets "
        f"({sum(r[3] for r in rows)} primary / {sum(r[4] for r in rows)} secondary).",
        "Ground truth: `ground_truth.json`.",
        "",
        "| file | variant | elements by kind | primary | secondary | total |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for f, var, kinds, p, s in sorted(rows):
        kd = ", ".join(f"{k}×{v}" for k, v in sorted(kinds.items()))
        lines.append(f"| `{f}` | {var} | {kd} | {p} | {s} | {p + s} |")
    lines.append("")
    (OUT / "index.md").write_text("\n".join(lines))
    return records


# ---------------------------------------------------------------- verification

STD_MIN = 3.5
OVERLAY_SCENES = ["slack-dark", "book-page-dark", "table-light", "dashboard-light"]


def verify() -> int:
    records = json.loads((OUT / "ground_truth.json").read_text())
    by_scene: dict[str, list[dict]] = {}
    for r in records:
        by_scene.setdefault(r["scene"], []).append(r)

    fails: list[str] = []
    worst: list[tuple[float, str, str]] = []
    n_checked = 0

    for scene, recs in sorted(by_scene.items()):
        p = OUT / scene
        if not p.exists():
            fails.append(f"{scene}: image missing")
            continue
        img = Image.open(p).convert("RGB")
        gray = img.convert("L")
        assert img.size == (W, H), f"{scene}: size {img.size}"
        ids: dict[str, int] = {}
        for r in recs:
            n_checked += 1
            eid = r["id"]
            ids[eid] = ids.get(eid, 0) + 1
            if ids[eid] > 1:
                fails.append(f"{scene}/{eid}: duplicate id")
            x, y, w, h = r["bbox"]
            if w <= 0 or h <= 0:
                fails.append(f"{scene}/{eid}: non-positive size {w}x{h}")
                continue
            if x < 0 or y < 0 or x + w > W or y + h > H:
                fails.append(f"{scene}/{eid}: out of bounds {r['bbox']}")
                continue
            s = float(np.asarray(gray.crop((x, y, x + w, y + h))).std())
            worst.append((s, scene, eid))
            if s < STD_MIN:
                fails.append(f"{scene}/{eid} ({r['kind']}): ink std {s:.2f} "
                             f"< {STD_MIN} -- box may be blank")

    worst.sort()
    print(f"checked {n_checked} boxes across {len(by_scene)} scenes")
    print(f"kinds used: {len(set(r['kind'] for r in records))}/{len(KINDS)}")
    print("lowest-variance boxes (std, scene, id):")
    for s, scene, eid in worst[:8]:
        print(f"  {s:7.2f}  {scene:22s} {eid}")
    if fails:
        print(f"\nFAIL ({len(fails)}):")
        for f in fails:
            print("  " + f)
    else:
        print("\nPASS: all boxes in bounds, non-degenerate, uniquely named, "
              f"and carry ink (min std {worst[0][0]:.2f} >= {STD_MIN})")

    for scene in OVERLAY_SCENES:
        recs = by_scene.get(f"{scene}.png")
        if not recs:
            continue
        img = Image.open(OUT / f"{scene}.png").convert("RGB")
        ov = ImageDraw.Draw(img, "RGBA")
        pal = {"primary": (255, 60, 60), "secondary": (70, 200, 255)}
        for r in sorted(recs, key=lambda r: -r["bbox"][2] * r["bbox"][3]):
            x, y, w, h = r["bbox"]
            col = pal[r["priority"]]
            ov.rectangle((x, y, x + w, y + h), outline=col + (255,),
                         width=4 if r["priority"] == "primary" else 2)
            lab = f"{r['kind']}:{r['id']}"
            f = F("sans-bold", 22)
            tw = ov.textlength(lab, font=f)
            ly = y + 2 if y < H - 40 else y - 26
            ov.rectangle((x, ly, x + tw + 10, ly + 28), fill=(0, 0, 0, 190))
            ov.text((x + 5, ly + 2), lab, font=f, fill=col + (255,))
        img.save(OUT / f"verify-{scene}.png")
        print(f"overlay -> verify-{scene}.png ({len(recs)} boxes)")

    return 1 if fails else 0


if __name__ == "__main__":
    if "--verify" in sys.argv:
        sys.exit(verify())
    generate()
    print()
    sys.exit(verify())
