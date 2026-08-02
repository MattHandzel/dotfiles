#!/usr/bin/env python3
"""kbshot — screenshot an object on screen, picked with the keyboard.

Press the hotkey, and every screenshot-worthy thing on the focused monitor gets a
labelled box: windows, text blocks, paragraphs, lines, and non-text UI rectangles
(cards, images, buttons). Type the label, get that region on the clipboard. The
mouse is never involved.

Those regions are offered a level at a time rather than all at once. The first
round is the biggest divisions of the screen; a letter picks one and the next
round offers only what lives inside it; Return captures what you have already
chosen rather than drilling further, and BackSpace goes back up a level. So the
keys you type spell out a path down a containment tree, which is what makes
regions that overlap share a prefix: everything inside the region labelled `u` is
reached by typing `u` first. On the eval corpus that takes the first screenful
from ~275 labels down to 25, and two regions sharing one key overlap by 24% on
average against 9% for two that share none. `--flat` restores the old
everything-at-once overlay.

The picker UI is wl-kbptr's `floating` mode, which takes arbitrary candidate areas
on stdin (`WxH+X+Y`, output-local logical coords) and prints the chosen one. Its own
built-in `source=detect` is deliberately NOT used: it filters out anything taller
than 50px or wider than 500px because it is hunting click targets, which is the
exact opposite of what a screenshot wants. Return and BackSpace are not things
floating mode knows about, so wl-kbptr-label-anchor.patch teaches it to report
them (see that patch and run_round).
"""

from __future__ import annotations

import argparse
import concurrent.futures
import contextlib
import fcntl
import threading
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

# Label alphabet, ordered and filtered for Matt's Dvorak layout.
#
#     ;  ,  .  P  Y  |  F  G  C  R  L
#     A  O  E  I  U  |  D  H  T  N  S
#     '  Q  J  K  X  |  B  M  W  V  Z
#
# Both of his keyboards produce this same layout -- the TOTEM does it in ZMK
# firmware (~/Projects/zmk-config-corne/config/totem.keymap) and the laptop's
# built-in keyboard does it in kanata (modules/core/kanata-homerow.nix) -- and both
# put hold-tap home-row mods on the same letters: o/n = Super, e/t = Alt,
# i/h = Ctrl, plus s and z as layer-taps on the TOTEM.
#
# A label's first character is by definition typed after a pause, and that is the
# case those mods are least protected in: ZMK's `require-prior-idle-ms` and
# kanata's `key-timing less-than 200` only suppress the hold behaviour when a key
# was pressed recently, so they cover the *second* character of a label but not
# the first.
#
# Matt's call (2026-07-31) is that this is fine in practice and the alphabet is
# not to be restricted -- hierarchical rounds need every letter they can get. So
# all 26 are available, ordered so the 18 plain `&kp` letters come first and the
# eight home-row-mod ones (i h e t o n s z) are the tail. Labels are handed out by
# index, so a round of 18 or fewer never reaches the tail at all, and a round of
# 19 to 26 stays one keystroke instead of spilling to two. Pass --labels to
# narrow it back down if a mod ever does fire.
LABEL_SYMBOLS = "udagcprfylmwkjvbxq" + "ihetonsz"

SAVE_DIR = Path.home() / "Pictures" / "Screenshots"

RUNTIME_DIR = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
LOCK_PATH = RUNTIME_DIR / "kbshot.lock"

# Screen-covering overlays from the *other* screenshot bindings. `grimblast --freeze`
# starts `hyprpicker -rz` as a fullscreen frozen-screen layer and then `slurp`.
COMPETING_OVERLAYS = ["hyprpicker", "slurp"]

# Never hold the keyboard longer than this. wl-kbptr takes an EXCLUSIVE layer-shell
# keyboard grab, so a wedged picker is not merely a stuck window -- it is a black hole
# for every keystroke, with no way out but killing it from elsewhere.
PICKER_TIMEOUT_S = 45

# Source tiers, in the order they win ties during dedupe (earlier = preferred).
#
# The xy-* tiers outrank their text-source equivalents on purpose. When an
# XY-cut region and a tesseract paragraph describe the same thing, the XY-cut box
# is the better screenshot: it hugs the ink and it includes the non-text parts
# that belong to the object (a message's avatar, a figure inside a column) which
# tesseract cannot see at all.
# Tiers naming a whole object rather than a fragment of one. These are what the
# overlay offers by default: outlining a region only helps if you can still see the
# screen through it, and 100 nested translucent rectangles is a wash of colour. Lines,
# words and tight sub-rectangles remain reachable with --all.
OBJECT_TIERS = ("window", "xy-pane", "block", "band", "xy-group", "rect-loose", "para")

TIER_ORDER = [
    "window",
    "xy-pane",
    "block",
    "xy-group",
    "band",
    "para",
    "rect-loose",
    "line",
    "xy-item",
    "rect-tight",
    "word",
]



@dataclass
class Box:
    """A candidate region, in output-local *logical* coordinates."""

    x: int
    y: int
    w: int
    h: int
    tier: str
    note: str = ""

    @property
    def area(self) -> int:
        return self.w * self.h

    def geom(self) -> str:
        return f"{self.w}x{self.h}+{self.x}+{self.y}"


def label_for(index: int, total: int, symbols: str = LABEL_SYMBOLS) -> str:
    """Reproduce wl-kbptr's label for candidate `index`, for debugging and tests.

    wl-kbptr encodes the index as fixed-width little-endian base-len(symbols), so
    the first character typed is the least-significant digit. Label width is uniform
    across all candidates, so with the default 18 symbols any screen offering 18 or
    fewer boxes is one keystroke and anything up to 324 is two.
    """
    width, n = 0, total
    while n > 0:
        width += 1
        n //= len(symbols)
    width = max(1, width)
    out = []
    for _ in range(width):
        out.append(symbols[index % len(symbols)])
        index //= len(symbols)
    return "".join(out)


def one_keystroke_max(symbols: str = LABEL_SYMBOLS) -> int:
    """Most areas wl-kbptr will still label with a single character.

    One less than the alphabet, not the alphabet: label.c sizes labels with
    `while (n > 0) { len++; n /= num_symbols; }`, so exactly 26 areas over 26
    symbols divides to 1 and takes a second pass. Getting this off by one made
    every round in the hierarchy cost two keystrokes instead of one.
    """
    return max(1, len(symbols) - 1)


def log(verbose: bool, *parts: object) -> None:
    if verbose:
        print("kbshot:", *parts, file=sys.stderr)


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=True, **kw)


def notify(summary: str, body: str = "", icon: str | None = None, urgency: str = "normal") -> None:
    if not shutil.which("notify-send"):
        return
    cmd = ["notify-send", "-a", "kbshot", "-u", urgency, summary]
    if body:
        cmd.append(body)
    if icon:
        cmd[1:1] = ["-i", icon]
    subprocess.run(cmd, check=False)


# --------------------------------------------------------------------------- #
# Not stacking overlays
#
# The failure this section exists to prevent: press CTRL+Print (kbshot's picker, an
# exclusive-keyboard layer surface) and then Print (grimblast --freeze, which stacks
# `hyprpicker -rz` fullscreen plus `slurp` on top). The screen ends up fully covered
# while the keyboard grab is held by a surface the user can no longer see, so Escape
# reaches nothing and there is no way out.
#
# Three independent defences, because any one of them can be defeated by a case not
# thought of here:
#   1. single-flight  -- a second kbshot replaces the first instead of stacking
#   2. clear rivals   -- tear down hyprpicker/slurp before taking the keyboard
#   3. watchdog       -- the picker is killed after PICKER_TIMEOUT_S no matter what
# Plus `kbshot --abort`, bound to a key, as the manual escape hatch.
# --------------------------------------------------------------------------- #


def kill_pid(pid: int, verbose: bool = False) -> None:
    """SIGTERM a pid, then SIGKILL it if it will not go."""
    for sig in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            return
        except PermissionError:
            return
        for _ in range(20):
            time.sleep(0.05)
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
        log(verbose, f"pid {pid} survived {sig.name}")


def clear_competing_overlays(verbose: bool = False) -> list[str]:
    """Tear down other screenshot overlays that would cover or fight for the screen.

    `pkill -x` matches the executable name exactly -- never `-f`, which would happily
    match this process's own command line or the shell that launched it.
    """
    cleared = []
    for name in COMPETING_OVERLAYS:
        if subprocess.run(["pkill", "-x", name], check=False).returncode == 0:
            cleared.append(name)
    if cleared:
        log(verbose, "cleared competing overlays:", ", ".join(cleared))
    return cleared


@contextlib.contextmanager
def single_flight(verbose: bool = False):
    """Ensure only one kbshot owns the screen; a newer press replaces an older one.

    Replace rather than refuse: pressing the hotkey again means the user wants a
    picker now, and leaving the stale one holding the keyboard is the whole bug.
    """
    lock = LOCK_PATH.open("a+")
    try:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            lock.seek(0)
            prev = lock.read().strip()
            if prev.isdigit() and int(prev) != os.getpid():
                log(verbose, f"replacing running kbshot (pid {prev})")
                kill_pid(int(prev), verbose)
            acquired = False
            for _ in range(60):
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    acquired = True
                    break
                except BlockingIOError:
                    time.sleep(0.05)
            if not acquired:
                notify(
                    "kbshot",
                    "Another kbshot is stuck holding the keyboard. Press CTRL+SHIFT+Print.",
                    urgency="critical",
                )
                sys.exit("kbshot: could not acquire the lock; try `kbshot --abort`")
        lock.seek(0)
        lock.truncate()
        lock.write(str(os.getpid()))
        lock.flush()
        yield
    finally:
        with contextlib.suppress(OSError):
            fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()


def abort(verbose: bool = False) -> int:
    """Kill every screenshot overlay, including a wedged picker. The escape hatch."""
    killed = list(COMPETING_OVERLAYS)
    cleared = clear_competing_overlays(verbose)
    # wl-kbptr is the one holding the exclusive keyboard grab, so it matters most.
    if subprocess.run(["pkill", "-x", "wl-kbptr"], check=False).returncode == 0:
        cleared.append("wl-kbptr")
    try:
        prev = LOCK_PATH.read_text().strip()
        if prev.isdigit() and int(prev) != os.getpid():
            kill_pid(int(prev), verbose)
            cleared.append(f"kbshot({prev})")
    except (OSError, ValueError):
        pass
    del killed
    if cleared:
        notify("kbshot", "Cleared: " + ", ".join(cleared))
        print("cleared: " + ", ".join(cleared))
    else:
        notify("kbshot", "No screenshot overlay was running")
        print("nothing to clear")
    return 0


# --------------------------------------------------------------------------- #
# Geometry: monitors and the pixel <-> logical mapping
# --------------------------------------------------------------------------- #


@dataclass
class Monitor:
    name: str
    ident: int
    # Global logical position of the output's top-left corner.
    x: int
    y: int
    # Physical framebuffer size, which is what grim hands us.
    px_w: int
    px_h: int
    # Logical size, i.e. the coordinate space wl-kbptr and grim -g speak.
    lg_w: int
    lg_h: int
    scale: float
    active_ws: int
    special_ws_id: int


def exact_scale(px_w: int, px_h: int, reported: float) -> tuple[float, int, int]:
    """Recover the exact scale factor from hyprctl's 2-decimal rounding.

    Wayland fractional scaling quantises the scale to 1/120 increments, and
    Hyprland only accepts a scale whose logical size is a whole number of pixels.
    So the true scale is k/120 for some integer k, and both px_w*120/k and
    px_h*120/k must be integers. Searching outward from round(reported*120)
    recovers it exactly: a reported 1.33 on a 2880x1800 panel resolves to 160/120
    = 4/3, giving 2160x1350 -- whereas naively dividing by 1.33 gives 2165x1353
    and every box lands a few pixels off.
    """
    target = reported * 120.0
    for delta in range(0, 25):
        for k in {round(target - delta), round(target + delta)}:
            if k <= 0:
                continue
            if (px_w * 120) % k or (px_h * 120) % k:
                continue
            return k / 120.0, px_w * 120 // k, px_h * 120 // k
    # Nothing divided cleanly; fall back to the rounded figure.
    return reported, round(px_w / reported), round(px_h / reported)


def synthetic_monitor(png: Path, scale: float) -> Monitor:
    """A Monitor standing in for a static image, so detection can run off-screen.

    This is what makes the tool testable. Detection quality is otherwise only
    observable by taking a real screenshot and squinting at it, which is not an
    eval -- it is an anecdote. With a synthetic monitor the same candidate pipeline
    runs against a corpus of saved screens and its output can be scored against
    hand-annotated ground truth.

    Scale defaults to 1.0 so that logical coordinates equal pixel coordinates,
    which means ground-truth boxes can be annotated in the image's own pixels with
    no conversion. Pass a real scale to exercise the fractional-scaling maths.
    """
    with Image.open(png) as im:
        px_w, px_h = im.width, im.height
    lg_w, lg_h = round(px_w / scale), round(px_h / scale)
    return Monitor(
        name=f"image:{png.name}",
        ident=-1,
        x=0,
        y=0,
        px_w=px_w,
        px_h=px_h,
        lg_w=lg_w,
        lg_h=lg_h,
        scale=scale,
        active_ws=0,
        special_ws_id=0,
    )


def get_monitor(want: str | None) -> Monitor:
    mons = json.loads(run(["hyprctl", "-j", "monitors"]).stdout)
    chosen = None
    if want:
        chosen = next((m for m in mons if m["name"] == want), None)
        if chosen is None:
            sys.exit(f"kbshot: no such output {want!r}")
    else:
        chosen = next((m for m in mons if m.get("focused")), mons[0])

    scale, lg_w, lg_h = exact_scale(chosen["width"], chosen["height"], chosen["scale"])
    return Monitor(
        name=chosen["name"],
        ident=chosen["id"],
        x=chosen["x"],
        y=chosen["y"],
        px_w=chosen["width"],
        px_h=chosen["height"],
        lg_w=lg_w,
        lg_h=lg_h,
        scale=scale,
        active_ws=chosen["activeWorkspace"]["id"],
        special_ws_id=chosen.get("specialWorkspace", {}).get("id", 0) or 0,
    )


# --------------------------------------------------------------------------- #
# Candidate sources
# --------------------------------------------------------------------------- #


def source_windows(mon: Monitor) -> list[Box]:
    """Window rectangles from Hyprland -- the highest-value boxes, and free."""
    try:
        clients = json.loads(run(["hyprctl", "-j", "clients"]).stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return []

    # Only workspaces actually on screen. A window on a hidden workspace would put
    # a labelled box over content that is not there, which is worse than missing
    # it -- the text and rect sources still cover whatever else is visible.
    visible_ws = {mon.active_ws}
    if mon.special_ws_id:
        visible_ws.add(mon.special_ws_id)

    boxes: list[Box] = []
    for c in clients:
        if not c.get("mapped") or c.get("hidden"):
            continue
        if c.get("monitor") != mon.ident:
            continue
        if c.get("workspace", {}).get("id") not in visible_ws:
            continue

        at, size = c.get("at"), c.get("size")
        if not at or not size or size[0] < 1 or size[1] < 1:
            continue
        note = (c.get("title") or c.get("class") or "").strip()
        boxes.append(
            Box(at[0] - mon.x, at[1] - mon.y, size[0], size[1], "window", note[:60])
        )
    return boxes


TESS_LEVELS = {2: "block", 3: "para", 4: "line", 5: "word"}


def source_text(png: Path, scale: float, ocr_scale: float, verbose: bool) -> list[Box]:
    """Text boxes at four granularities, straight out of tesseract's TSV.

    Tesseract's layout analysis already gives us exactly the nesting the request
    called for -- level 2 blocks, 3 paragraphs, 4 lines, 5 words -- so no grouping
    heuristics are needed on top of it.
    """
    if not shutil.which("tesseract"):
        log(verbose, "tesseract not found, skipping text source")
        return []

    src = png
    tmp = None
    if ocr_scale != 1.0:
        # OCR on a downscaled copy. Half-size costs ~1.5s where native costs ~4.3s
        # on a text-dense screen, and the box geometry we actually want is just as
        # good -- only the recognised characters degrade, and those are a bonus.
        img = Image.open(png)
        tmp = png.with_name("ocr-input.png")
        img.resize(
            (max(1, round(img.width * ocr_scale)), max(1, round(img.height * ocr_scale))),
            Image.LANCZOS,
        ).save(tmp)
        src = tmp

    # OMP_THREAD_LIMIT=1 is not a typo. Tesseract's OpenMP path is a net loss here:
    # on this 8-core laptop the same page takes 1.5s single-threaded and 2.5s with
    # 8 threads, because the threads contend more than they help.
    env = dict(os.environ, OMP_THREAD_LIMIT="1")

    try:
        out = subprocess.run(
            ["tesseract", str(src), "-", "--psm", "3", "-c", "tessedit_do_invert=0", "tsv"],
            capture_output=True,
            text=True,
            check=True,
            env=env,
        ).stdout
    except subprocess.CalledProcessError as exc:
        log(verbose, "tesseract failed:", exc.stderr.strip()[:200])
        return []
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)

    # Boxes come out in OCR-input pixels; convert to logical.
    px_to_logical = 1.0 / (scale * ocr_scale)

    boxes: list[Box] = []
    for raw in out.splitlines()[1:]:
        f = raw.split("\t")
        if len(f) < 11:
            continue
        try:
            level = int(f[0])
            left, top, width, height = (int(f[i]) for i in (6, 7, 8, 9))
            conf = float(f[10])
        except ValueError:
            continue
        tier = TESS_LEVELS.get(level)
        if tier is None:
            continue
        text = f[11].strip() if len(f) > 11 else ""
        if tier == "word" and (conf < 40 or not text):
            continue
        if width < 6 or height < 6:
            continue
        boxes.append(
            Box(
                round(left * px_to_logical),
                round(top * px_to_logical),
                round(width * px_to_logical),
                round(height * px_to_logical),
                tier,
                text[:40],
            )
        )
    return boxes


def source_rects(png: Path, scale: float, detect_width: int, verbose: bool) -> list[Box]:
    """Non-text UI rectangles: cards, images, code blocks, panels, buttons.

    Sobel edges -> morphological closing -> connected components -> bounding boxes.
    Two closing radii are used because the request wanted both granularities: the
    tight pass isolates individual elements, the loose pass merges them into the
    surrounding panel.

    Runs on a downscaled copy. Panel-finding does not need native resolution, and
    at 2880x1800 the dilation alone cost more than two seconds -- unacceptable when
    this sits between a keypress and an overlay appearing.
    """
    img = Image.open(png).convert("L")
    f = min(1.0, detect_width / img.width)
    if f < 1.0:
        img = img.resize((round(img.width * f), round(img.height * f)), Image.BILINEAR)
    grey = np.asarray(img, dtype=np.float32)

    gx = ndimage.sobel(grey, axis=1)
    gy = ndimage.sobel(grey, axis=0)
    edges = np.hypot(gx, gy) > 90.0

    # Detect-pixels -> logical: undo the downscale, then undo the output scale.
    to_logical = 1.0 / (scale * f)
    lg_w, lg_h = grey.shape[1] * to_logical, grey.shape[0] * to_logical

    boxes: list[Box] = []
    # (tier, closing extent in logical px as (vertical, horizontal))
    for tier, (kv, kh) in (("rect-tight", (3, 4)), ("rect-loose", (9, 17))):
        # maximum_filter on a boolean array is a dilation, and scipy applies a
        # `size` tuple separably -- orders of magnitude cheaper than passing an
        # equivalent 2D structure to binary_dilation.
        sv = max(1, round(kv * scale * f))
        sh = max(1, round(kh * scale * f))
        closed = ndimage.maximum_filter(edges, size=(sv, sh), mode="nearest")
        labels, count = ndimage.label(closed)
        if count == 0:
            continue
        found = 0
        for sl in ndimage.find_objects(labels):
            if sl is None:
                continue
            ys, xs = sl
            x, y = xs.start * to_logical, ys.start * to_logical
            w = (xs.stop - xs.start) * to_logical
            h = (ys.stop - ys.start) * to_logical
            # Too small to be worth a label; the near-full-screen blob is already
            # offered as its own candidate.
            if w < 24 or h < 14:
                continue
            if w > lg_w * 0.99 and h > lg_h * 0.99:
                continue
            boxes.append(Box(round(x), round(y), round(w), round(h), tier))
            found += 1
        log(verbose, f"{tier}: {found} rects from {count} components")
    return boxes


# A projection slot counts as blank when its ink is at or below this fraction of
# the span. Zero does not work: measured on a real desktop frame, the quietest row
# still carries 8px of ink out of 1440 because a window separator runs the full
# height, so a strict test finds no gutter anywhere and XY-cut degenerates to a
# single box. 1.2% sits just above that noise floor and just below the ink of the
# sparsest real text line -- at 1% a live frame yielded 21 gutters including a 91px
# one, at 0.5% it yielded none.
XY_BLANK_TOL = 0.012

# Upper bound on XY-cut nodes. Cutting on both axes at every level branches, so a
# pathological screen could otherwise spend real time enumerating regions that the
# budget will throw away anyway. Dedupe and apply_budget cut this to ~220 regardless.
XY_NODE_CAP = 4000

# Toggled by the eval harness to A/B the divider-suppression pass.
# Divider suppression turned out to be a net LOSS and is off by default. It does what
# it claims -- a thin full-span rule becomes a gutter -- but a card border is also a
# full-span rule relative to the node it sits in, so erasing it shrank card boxes to
# their inner content and cards fell from 18/20 to 9/20 while table rows did not move
# at all. Kept, off, because the reasoning is sound and a future node-aware version
# (suppress only at the top level) may still pay off.
XY_SUPPRESS_RULES = os.environ.get("KBSHOT_SUPPRESS_RULES", "0") != "0"
XY_EDGE_THRESHOLDS = tuple(
    float(t) for t in os.environ.get("KBSHOT_XY_EDGE", "45").split(",")
)


def _thin_runs(flags: np.ndarray, max_thick: int) -> list[tuple[int, int]]:
    """Runs of True in `flags` no longer than `max_thick`."""
    padded = np.concatenate(([False], flags, [False]))
    d = np.diff(padded.astype(np.int8))
    out = []
    for s, e in zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1)):
        if e - s <= max_thick:
            out.append((int(s), int(e)))
    return out


def _suppress_rules(ink: np.ndarray, max_thick: int) -> np.ndarray:
    """Erase thin full-span lines from the ink mask, turning dividers into gutters.

    Without this, XY-cut is blind to any boundary drawn as a LINE rather than left as
    whitespace -- and that is how most real UIs separate things. A table's row
    striping and gridlines, a settings pane's list separators, the rule under a
    heading: each paints an edge clean across the full width, so that row of the
    projection profile is 100% ink and reads as the densest possible content instead
    of as a boundary. Measured on the table scene, this was the entire reason row
    detection sat at 2/28: the best candidate for a row overlapped it by 0.19.

    A separator is distinguished from real content by being BOTH full-span and thin.
    A photograph also produces full-span high-ink rows, but hundreds of them in a row,
    so the thickness limit leaves it alone. Erasing a divider merges the padding on
    either side of it into one gutter wide enough for XY-cut to cut on.
    """
    h, w = ink.shape
    out = ink.copy()
    # 0.9 rather than 1.0: antialiasing and rounded corners mean a rule rarely
    # reaches literally every column.
    row_full = (ink.sum(axis=1) / max(1, w)) >= 0.90
    for s, e in _thin_runs(row_full, max_thick):
        out[s:e, :] = False
    col_full = (out.sum(axis=0) / max(1, h)) >= 0.90
    for s, e in _thin_runs(col_full, max_thick):
        out[:, s:e] = False
    return out


def _blank_profile(mask: np.ndarray, axis: int) -> np.ndarray:
    """Per-slot blankness along `axis`, with the noise tolerance applied."""
    counts = mask.sum(axis=axis)
    span = mask.shape[1 - axis]
    return counts <= max(1, int(XY_BLANK_TOL * span))


def _gap_runs(blank: np.ndarray, min_gap: int) -> list[tuple[int, int]]:
    """Runs of `min_gap` or more consecutive blank slots in a projection profile.

    Returns (start, stop) index pairs. Runs touching either end are ignored: the
    caller has already trimmed the node to its ink, so an edge run means nothing.
    """
    if blank.size == 0:
        return []
    # Difference of the padded boolean gives run starts (+1) and stops (-1).
    padded = np.concatenate(([False], blank, [False]))
    d = np.diff(padded.astype(np.int8))
    starts = np.flatnonzero(d == 1)
    stops = np.flatnonzero(d == -1)
    out = []
    for s, e in zip(starts, stops):
        if s == 0 or e == blank.size:
            continue
        if e - s >= min_gap:
            out.append((int(s), int(e)))
    return out


def _xycut(
    mask: np.ndarray,
    x0: int,
    y0: int,
    depth: int,
    out: list[tuple[int, int, int, int, int]],
    min_gap: int,
    min_side: int,
    max_depth: int,
) -> None:
    """Recursive XY-cut: split a region at its widest whitespace gutters.

    This is the classic document-layout algorithm and it is the piece that was
    missing. Tesseract gives text boxes and the sobel pass gives drawn
    rectangles, but neither can see a region that is defined purely by the
    WHITESPACE around it -- which is exactly what a chat message, a paragraph, a
    card, and a column all are. A Slack message has no border to detect and its
    author line, avatar and body are separate text blocks to tesseract; what
    makes it one object is the blank band above and below it.

    Each recursion level emits its own trimmed bounding box, so the output is a
    containment hierarchy (pane -> column -> message -> line) rather than a flat
    list, and a nested element stays independently selectable.
    """
    h, w = mask.shape
    if h < min_side or w < min_side or depth > max_depth:
        return

    row_ink = ~_blank_profile(mask, 1)
    if not row_ink.any():
        return
    col_ink = ~_blank_profile(mask, 0)
    if not col_ink.any():
        return
    # Trim blank margins so the emitted box hugs the ink rather than the slot it
    # happened to be cut from -- an untrimmed box captures a band of background.
    r0 = int(row_ink.argmax())
    r1 = h - int(row_ink[::-1].argmax())
    c0 = int(col_ink.argmax())
    c1 = w - int(col_ink[::-1].argmax())
    sub = mask[r0:r1, c0:c1]
    sh, sw = sub.shape
    if sh < min_side or sw < min_side:
        return

    out.append((x0 + c0, y0 + r0, sw, sh, depth))
    if len(out) >= XY_NODE_CAP:
        return

    # Cut on BOTH axes rather than choosing one.
    #
    # Textbook XY-cut alternates axes, or picks whichever has the widest gutter. Both
    # are wrong here, and a table shows why: its column gutters are wider than its row
    # gutters, so a widest-gutter rule splits into columns first and then into rows
    # *within* a column -- meaning the only boxes it can ever emit are cells, and a
    # full-width row is unreachable. Measured before this change, the best candidate
    # for any table row overlapped it by 0.19, which is almost exactly the 1/6 you
    # would expect from a single cell of a six-column table.
    #
    # A screenshot picker does not have to choose. Offering the row decomposition and
    # the column decomposition as alternatives is exactly the nested-alternatives
    # behaviour the tool wants, and dedupe drops whichever turns out redundant.
    for axis in (0, 1):
        blank = _blank_profile(sub, 1 - axis)
        gaps = _gap_runs(blank, min_gap)
        if not gaps:
            continue
        widths = sorted({e - s for s, e in gaps}, reverse=True)

        # Cut at several gutter widths, not one.
        #
        # A single threshold cannot serve a table. Its inter-row gutters are all the
        # same modest width, so any threshold derived from the widest gap in the node
        # -- the gap above the header, say -- discards every one of them, and rows
        # become unreachable. That was measured: table rows sat at 2/28 with a
        # widest*0.5 threshold even after cutting on both axes, because the row
        # gutters were 7-10px against a threshold of 15.
        #
        # Cutting at the widest gutter, at a typical gutter, and at the smallest
        # yields the coarse decomposition (sections), the medium one (rows,
        # paragraphs, messages) and the fine one (lines) as alternatives. Only shallow
        # nodes get all three, because deep nodes are already small and the branching
        # would buy nothing but nodes for dedupe to throw away.
        levels = 3 if depth <= 1 else (2 if depth <= 3 else 1)
        thresholds = []
        for t in (widths[0], widths[len(widths) // 2], widths[-1])[:levels]:
            t = max(float(min_gap), float(t))
            if t not in thresholds:
                thresholds.append(t)

        span = sh if axis == 0 else sw
        for t in thresholds:
            keep = [g for g in gaps if (g[1] - g[0]) >= t]
            bounds = [0] + [m for g in keep for m in (g[0], g[1])] + [span]
            pieces = [(bounds[i], bounds[i + 1]) for i in range(0, len(bounds) - 1, 2)]
            if len(pieces) < 2:
                continue  # a single piece is just this node again
            # Gutter midpoints, so a piece can also be offered WITH its padding.
            # Trimming to ink is right for a paragraph but wrong for a table row or a
            # list item: the thing a person means by "that row" is the whole striped
            # band, padding included, and a box hugging just the glyphs looks cropped.
            # Measured, this is the difference between IoU 0.43 and 0.95 on a table
            # row. Both variants are emitted and dedupe keeps whichever is distinct.
            mids = [0] + [(g[0] + g[1]) // 2 for g in keep] + [span]
            for idx, (a, b) in enumerate(pieces):
                if b - a < min_side:
                    continue
                if len(out) >= XY_NODE_CAP:
                    return
                pa, pb = mids[idx], mids[idx + 1]
                if (pb - pa) - (b - a) >= 4 and pb - pa >= min_side:
                    if axis == 0:
                        out.append((x0 + c0, y0 + r0 + pa, sw, pb - pa, depth + 1))
                    else:
                        out.append((x0 + c0 + pa, y0 + r0, pb - pa, sh, depth + 1))
                if axis == 0:
                    _xycut(sub[a:b, :], x0 + c0, y0 + r0 + a, depth + 1, out,
                           max(2, min_gap // 2), min_side, max_depth)
                else:
                    _xycut(sub[:, a:b], x0 + c0 + a, y0 + r0, depth + 1, out,
                           max(2, min_gap // 2), min_side, max_depth)


# A background band must differ from its neighbours by at least this many luma levels
# to count as a real step. Light-theme table striping measures 3-8 levels here, well
# under any usable sobel threshold, which is exactly why this channel exists.
BAND_STEP_MIN = 2.0
# ...and rows within one band must agree to within this, so a gradient drifts rather
# than stepping and produces no bands at all.
BAND_FLAT_TOL = 1.5


def _bg_profile(grey: np.ndarray, ink: np.ndarray, axis: int) -> np.ndarray:
    """Median of the NON-ink pixels along `axis` -- i.e. the background colour.

    The median is the whole point: it throws away glyphs, anti-aliasing and the odd
    icon, so what survives is the paint behind the content. A mean would be dragged
    around by how much text a row happens to contain.
    """
    masked = np.where(ink, np.nan, grey)
    with np.errstate(all="ignore"):
        prof = np.nanmedian(masked, axis=axis)
    # A row that is entirely ink has no background; carry the neighbouring value
    # rather than leaving a hole that would read as a step.
    bad = ~np.isfinite(prof)
    if bad.all():
        return np.zeros_like(prof)
    idx = np.arange(prof.size)
    prof[bad] = np.interp(idx[bad], idx[~bad], prof[~bad])
    return prof


def _flat_bands(prof: np.ndarray, min_len: int) -> list[tuple[int, int]]:
    """Maximal runs where the profile is flat, split where it steps."""
    bands: list[tuple[int, int]] = []
    start = 0
    for i in range(1, prof.size):
        if abs(prof[i] - prof[i - 1]) > BAND_FLAT_TOL:
            if i - start >= min_len:
                bands.append((start, i))
            start = i
    if prof.size - start >= min_len:
        bands.append((start, prof.size))
    return bands


def source_bands(
    png: Path,
    scale: float,
    detect_width: int,
    verbose: bool,
    seeds: list[Box] | None = None,
) -> list[Box]:
    """Regions whose only signal is a faint background tint.

    A third kind of boundary, invisible to the other three sources. Tesseract sees
    text, the sobel pass sees drawn edges, and XY-cut sees whitespace -- but a table's
    zebra striping, a tinted code block and a callout panel are none of those. They
    are a *painted background*, differing from the page by a handful of luma levels:
    far too little for any edge threshold that is not also picking up noise, yet
    perfectly crisp once you look at the background colour directly.

    This is why light-theme table rows scored 0/14 while dark-theme rows scored 13/14.
    It is also the reason the extents were wrong rather than merely missing: a row's
    ink may start a third of the way across, but the painted stripe spans the whole
    table, and the stripe is what a person means by "that row".
    """
    img = Image.open(png).convert("L")
    f = min(1.0, detect_width / img.width)
    if f < 1.0:
        img = img.resize((round(img.width * f), round(img.height * f)), Image.BILINEAR)
    grey = np.asarray(img, dtype=np.float32)
    dh, dw = grey.shape

    gx = ndimage.sobel(grey, axis=1)
    gy = ndimage.sobel(grey, axis=0)
    # Dilated generously: the median must not see glyph interiors, only paint.
    ink = ndimage.maximum_filter(np.hypot(gx, gy) > 40.0, size=(5, 5), mode="constant",
                                 cval=False)

    to_logical = 1.0 / (scale * f)
    min_side = max(6, round(12 * scale * f))

    regions: list[tuple[int, int, int, int]] = [(0, 0, dw, dh)]
    for b in seeds or []:
        x0 = max(0, min(dw - 1, round(b.x * scale * f)))
        y0 = max(0, min(dh - 1, round(b.y * scale * f)))
        x1 = max(x0 + 1, min(dw, round((b.x + b.w) * scale * f)))
        y1 = max(y0 + 1, min(dh, round((b.y + b.h) * scale * f)))
        if (x1 - x0) >= min_side * 2 and (y1 - y0) >= min_side * 2:
            regions.append((x0, y0, x1 - x0, y1 - y0))

    boxes: list[Box] = []
    for rx, ry, rw, rh in regions:
        g = grey[ry:ry + rh, rx:rx + rw]
        k = ink[ry:ry + rh, rx:rx + rw]
        rows = _bg_profile(g, k, 1)
        bands = _flat_bands(rows, min_side)
        if len(bands) < 2:
            continue

        kept: list[tuple[int, int, int, int, float]] = []
        for a, b in bands:
            level = float(np.median(rows[a:b]))
            # Must actually step away from at least one neighbour, or this is just a
            # slice of uniform page and not a region at all.
            neigh = [float(np.median(rows[p:q])) for p, q in bands if (p, q) != (a, b)]
            if not any(abs(level - n) >= BAND_STEP_MIN for n in neigh):
                continue
            # Horizontal extent of the paint: the longest run of columns whose own
            # background matches this band. This is what recovers the full stripe
            # width when the row's ink covers only part of it.
            cols = _bg_profile(g[a:b, :], k[a:b, :], 0)
            match = np.abs(cols - level) <= max(BAND_FLAT_TOL, BAND_STEP_MIN - 0.5)
            best_len = best_start = 0
            cur = 0
            for i, m in enumerate(match):
                cur = cur + 1 if m else 0
                if cur > best_len:
                    best_len, best_start = cur, i - cur + 1
            if best_len < min_side:
                continue
            kept.append((best_start, a, best_len, b - a, level))

        for bx, by, bw, bh, _lvl in kept:
            lw, lh = bw * to_logical, bh * to_logical
            if lw < 24 or lh < 14:
                continue
            boxes.append(Box(round((rx + bx) * to_logical), round((ry + by) * to_logical),
                             round(lw), round(lh), "band"))

        # The alternating run itself is a region too -- that is the whole table, or the
        # whole striped list, which is a thing people screenshot as a unit.
        if len(kept) >= 3:
            xs = min(k2[0] for k2 in kept)
            xe = max(k2[0] + k2[2] for k2 in kept)
            ys = min(k2[1] for k2 in kept)
            ye = max(k2[1] + k2[3] for k2 in kept)
            boxes.append(Box(round((rx + xs) * to_logical), round((ry + ys) * to_logical),
                             round((xe - xs) * to_logical), round((ye - ys) * to_logical),
                             "band"))

    log(verbose, f"bands: {len(boxes)} regions from {len(regions)} seeds")
    return boxes


def source_xycut(
    png: Path,
    scale: float,
    detect_width: int,
    verbose: bool,
    seeds: list[Box] | None = None,
) -> list[Box]:
    """Whitespace-defined regions: chat messages, paragraphs, columns, cards.

    Tiered by how much of the screen the region covers rather than by recursion
    depth, because depth is not comparable between a shallow dashboard and a
    deeply nested chat pane, whereas "this is a third of the screen" means the
    same thing in both.

    `seeds` are regions to cut INSIDE, normally the window rectangles. Passing them
    is not an optimisation, it is what makes this source work on a real desktop at
    all. Run on the whole screen, persistent chrome bridges every gutter: a row of
    pixels through the empty middle of the screen still crosses a full-height
    browser sidebar, and a column still crosses the full-width taskbar, so neither
    projection ever falls under the blank tolerance and nothing is cut. Measured on
    a real frame, screen-level cutting produced 2 regions where per-window cutting
    produces dozens -- while the synthetic single-app scenes, having no chrome, hid
    the problem completely.
    """
    img = Image.open(png).convert("L")
    f = min(1.0, detect_width / img.width)
    if f < 1.0:
        img = img.resize((round(img.width * f), round(img.height * f)), Image.BILINEAR)
    grey = np.asarray(img, dtype=np.float32)

    gx = ndimage.sobel(grey, axis=1)
    gy = ndimage.sobel(grey, axis=0)
    mag = np.hypot(gx, gy)

    to_logical = 1.0 / (scale * f)
    total_lg = (grey.shape[1] * to_logical) * (grey.shape[0] * to_logical)

    # ~10 logical px is wider than line leading but narrower than a paragraph or
    # inter-message gap, so the first cuts land on real structure.
    min_gap = max(2, round(10 * scale * f))
    min_side = max(6, round(12 * scale * f))

    dh, dw = grey.shape

    # Cut inside each window, plus the whole screen as a fallback so a compositor
    # without window data (or --from-image) still gets something.
    regions: list[tuple[int, int, int, int]] = [(0, 0, dw, dh)]
    for b in seeds or []:
        x0 = max(0, min(dw - 1, round(b.x * scale * f)))
        y0 = max(0, min(dh - 1, round(b.y * scale * f)))
        x1 = max(x0 + 1, min(dw, round((b.x + b.w) * scale * f)))
        y1 = max(y0 + 1, min(dh, round((b.y + b.h) * scale * f)))
        if (x1 - x0) >= min_side * 2 and (y1 - y0) >= min_side * 2:
            regions.append((x0, y0, x1 - x0, y1 - y0))

    nodes: list[tuple[int, int, int, int, int]] = []
    for thresh in XY_EDGE_THRESHOLDS:
        edges = mag > thresh
        # Bridge the sub-pixel gaps between glyph strokes so a text line reads as one
        # continuous ink run instead of a picket fence of blank columns.
        ink = ndimage.maximum_filter(edges, size=(2, 3), mode="constant", cval=False)
        for rx, ry, rw, rh in regions:
            _xycut(ink[ry:ry + rh, rx:rx + rw], rx, ry, 0, nodes,
                   min_gap, min_side, 7)

    boxes: list[Box] = []
    for x, y, w, h, _depth in nodes:
        lx, ly = x * to_logical, y * to_logical
        lw, lh = w * to_logical, h * to_logical
        if lw < 24 or lh < 14:
            continue
        frac = (lw * lh) / max(1.0, total_lg)
        if frac > 0.25:
            tier = "xy-pane"
        elif frac > 0.004:
            tier = "xy-group"
        else:
            tier = "xy-item"
        boxes.append(Box(round(lx), round(ly), round(lw), round(lh), tier))
    log(verbose, f"xycut: {len(boxes)} regions from {len(nodes)} nodes")
    return boxes


# --------------------------------------------------------------------------- #
# Dedupe and budget
# --------------------------------------------------------------------------- #


def dedupe(boxes: list[Box], iou_max: float = 0.88) -> list[Box]:
    """Drop boxes that are near-duplicates of an already-kept box.

    Sorted so that the preferred tier and the larger box win, then a vectorised
    IoU check against everything kept so far. Vectorised because a busy screen
    produces a couple of thousand candidates and an O(n^2) Python loop over that
    adds seconds to a keypress.
    """
    rank = {t: i for i, t in enumerate(TIER_ORDER)}
    ordered = sorted(boxes, key=lambda b: (rank.get(b.tier, 99), -b.area))

    kept: list[Box] = []
    kx = np.empty(0)
    ky = np.empty(0)
    kx2 = np.empty(0)
    ky2 = np.empty(0)
    karea = np.empty(0)

    for b in ordered:
        if b.w < 1 or b.h < 1:
            continue
        if len(kept):
            ix1 = np.maximum(kx, b.x)
            iy1 = np.maximum(ky, b.y)
            ix2 = np.minimum(kx2, b.x + b.w)
            iy2 = np.minimum(ky2, b.y + b.h)
            iw = np.clip(ix2 - ix1, 0, None)
            ih = np.clip(iy2 - iy1, 0, None)
            inter = iw * ih
            union = karea + b.area - inter
            if np.any(inter / np.maximum(union, 1) > iou_max):
                continue
        kept.append(b)
        kx = np.append(kx, b.x)
        ky = np.append(ky, b.y)
        kx2 = np.append(kx2, b.x + b.w)
        ky2 = np.append(ky2, b.y + b.h)
        karea = np.append(karea, b.area)

    return kept


def apply_budget(boxes: list[Box], cap: int) -> list[Box]:
    """Trim to `cap` boxes while keeping every tier represented.

    A straight truncation by tier order would let 400 text lines eat the entire
    budget and leave no image or panel boxes at all, so this round-robins across
    tiers instead.
    """
    if len(boxes) <= cap:
        return boxes
    buckets: dict[str, list[Box]] = {}
    for b in boxes:
        buckets.setdefault(b.tier, []).append(b)
    for tier in buckets:
        buckets[tier].sort(key=lambda b: -b.area)

    out: list[Box] = []
    tiers = [t for t in TIER_ORDER if t in buckets]
    while len(out) < cap and any(buckets[t] for t in tiers):
        for t in tiers:
            if buckets[t] and len(out) < cap:
                out.append(buckets[t].pop(0))
    return out


def clip_to_output(boxes: list[Box], mon: Monitor, min_w: int, min_h: int) -> list[Box]:
    """Clip to the output and drop anything too small to be worth a label.

    A minimum size does real work here: sub-20px fragments are almost never what
    someone wants a screenshot of, they crowd out the boxes that are, and each one
    consumes a label. Raising the floor makes the remaining labels both fewer and
    easier to tell apart.
    """
    out = []
    for b in boxes:
        x1, y1 = max(0, b.x), max(0, b.y)
        x2, y2 = min(mon.lg_w, b.x + b.w), min(mon.lg_h, b.y + b.h)
        if x2 - x1 < min_w or y2 - y1 < min_h:
            continue
        out.append(Box(x1, y1, x2 - x1, y2 - y1, b.tier, b.note))
    return out


def pick_corners(
    mon: Monitor, timeout: float, verbose: bool, theme: str = "default"
) -> tuple[int, int, int, int] | None:
    """Select an arbitrary region by typing two corners, with no object detection.

    wl-kbptr's `tile,bisect` chain is a recursive subdivision of the screen: the tile
    grid narrows to a cell by typed label, then bisect halves it repeatedly with the
    arrow-ish keys until it is a point. Running that twice gives two points, and the
    rectangle between them is the region -- so anything the object detector misses or
    splits wrongly is still reachable, precisely, without a mouse.
    """
    pal = THEMES.get(theme, THEMES["default"])
    points = []
    for which in ("top-left", "bottom-right"):
        notify("kbshot", f"Pick the {which} corner", urgency="low")
        cmd = [
            "wl-kbptr", "-O", mon.name, "-p",
            "-o", "modes=tile,bisect",
            "-o", "home_row_keys=asdfjkl;qwe",
            "-o", "mode_tile.label_symbols=udagcprfylmwkjvbxq",
            "-o", "mode_tile.label_font_size=16 40% 60",
            # Corner mode's tiles are large, so a translucent fill is fine here --
            # the label sits on a big block of one colour rather than on arbitrary
            # content. Only the palette's label and border colours carry over.
            "-o", f"mode_tile.label_color={pal['label']}",
            "-o", f"mode_tile.label_select_color={pal['typed']}",
            "-o", f"mode_tile.selectable_border_color={pal['border']}",
            "-o", f"mode_tile.unselectable_bg_color={pal['dim']}",
            "-o", f"mode_bisect.label_color={pal['label']}",
            "-o", f"mode_bisect.unselectable_bg_color={pal['dim']}",
            "-o", "general.cancellation_status_code=1",
        ]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        except subprocess.TimeoutExpired:
            log(verbose, "corner picker timed out")
            return None
        if proc.returncode != 0 or not proc.stdout.strip():
            log(verbose, f"cancelled at the {which} corner")
            return None
        m = RESULT_RE.match(proc.stdout.strip())
        if not m:
            return None
        w, h, x, y, ox, oy = (int(g) for g in m.groups())
        # bisect narrows to a small area; its centre is the point the user aimed at.
        points.append((x + w // 2 + ox, y + h // 2 + oy))
        log(verbose, f"{which} corner: {points[-1]}")

    (x1, y1), (x2, y2) = points
    left, right = min(x1, x2), max(x1, x2)
    top, bottom = min(y1, y2), max(y1, y2)
    if right - left < 2 or bottom - top < 2:
        notify("kbshot", "Those two corners are the same point", urgency="critical")
        return None
    return left, top, right - left, bottom - top


# --------------------------------------------------------------------------- #
# The region hierarchy
# --------------------------------------------------------------------------- #
#
# Offering all ~280 candidates at once makes picking the right one guesswork:
# the labels say nothing about how the regions relate, so two characters that
# differ in the first position can name a paragraph and the window around it.
#
# So the regions are arranged into a containment forest first, and the picker
# walks it one level at a time: the biggest regions are offered, one keystroke
# chooses one, and the next round offers only what lives inside that choice. The
# sequence of keys you type IS the path down the tree, which is what "regions
# that overlap share a prefix" means in practice -- everything inside the region
# labelled `u` is reached by typing `u` first, with no exceptions to remember.
#
# The tree is built ONCE from the full candidate set. Re-running detection on the
# chosen region instead would be wrong: the detectors work off whole-screen
# projections and connected components, and a component that straddles the
# region's edge would either vanish or come back with different bounds, so
# drilling in would change the answers rather than narrow them.

# Fraction of a candidate that must lie inside a bigger one for that bigger one to
# be its parent. Deliberately below 1: a paragraph whose bullet or scrollbar pokes
# a few px outside its column still belongs to that column.
CONTAIN_MIN = 0.80

# Same measure, but for the weaker relation used when a level has more regions
# than one keystroke can label and the overflow has to be pushed a level deeper.
# "Mostly overlapping" is the most that can be asked there.
OVERLAP_MIN = 0.45

# How full to make a round before stopping. 0 means "as full as one keystroke
# allows", and that is the right default rather than a compromise: every round
# costs exactly one keystroke whether it holds 3 regions or 26, so a thin round is
# a keystroke that bought almost no information. Filling rounds up is what keeps
# the tree shallow -- left at 6 it measured 5.4 keystrokes to a target and 7
# rounds deep on a Slack screen, worse than the flat picker it replaces.
ROUND_MIN = 0


@dataclass
class Node:
    """A region and the regions that live inside it."""

    box: Box
    kids: list["Node"] = field(default_factory=list)
    parent: "Node | None" = None

    def walk(self):
        yield self
        for k in self.kids:
            yield from k.walk()


def coverage(inner: Box, outer: Box) -> float:
    """Fraction of `inner`'s area that lies inside `outer`."""
    ix = max(0, min(inner.x + inner.w, outer.x + outer.w) - max(inner.x, outer.x))
    iy = max(0, min(inner.y + inner.h, outer.y + outer.h) - max(inner.y, outer.y))
    return (ix * iy) / max(1, inner.area)


def _sort_key(n: "Node") -> tuple[int, int, int, int, int]:
    # Largest first, then reading order. Total, so two runs on the same screen
    # build the same tree and the same labels -- muscle memory needs that.
    return (-n.box.area, n.box.y, n.box.x, n.box.w, n.box.h)


def build_hierarchy(
    boxes: list[Box],
    mon: Monitor,
    contain_min: float = CONTAIN_MIN,
    overlap_min: float = OVERLAP_MIN,
    round_max: int | None = None,
) -> Node:
    """Arrange the candidates into a containment tree rooted at the whole output.

    A region's parent is the SMALLEST candidate that swallows at least
    `contain_min` of it. Scanning largest-first and keeping the last match gives
    exactly that, and can never produce a cycle because a parent is always
    strictly earlier in a total order.
    """
    root = Node(Box(0, 0, mon.lg_w, mon.lg_h, "screen", "whole screen"))
    # The whole-output candidate IS the root, and offering it inside its own round
    # would be a label for "what you already have". Everything else, including a
    # maximised window a few px short of the output, stays a normal level: a round
    # holding only it gets its children promoted up beside it, so nothing is lost.
    nodes = [
        Node(b)
        for b in boxes
        if not (b.x <= 0 and b.y <= 0 and b.w >= mon.lg_w and b.h >= mon.lg_h)
    ]
    nodes.sort(key=_sort_key)

    for i, child in enumerate(nodes):
        host = root
        for j in range(i):
            if coverage(child.box, nodes[j].box) >= contain_min:
                host = nodes[j]  # keep the last, i.e. the smallest container
        child.parent = host
        host.kids.append(child)

    if round_max:
        _cap_rounds(root, overlap_min, round_max)
    return root


def _cap_rounds(root: Node, overlap_min: float, round_max: int) -> None:
    """Keep a round to one keystroke by pushing the overflow a level deeper.

    The regions kept are the biggest ones, which is the point: the first thing you
    are asked to choose between is always the coarsest division of the screen. An
    overflow region goes under whichever kept sibling it mostly overlaps. One that
    overlaps none of them stays in the round -- a round of 27 costs a second
    keystroke, but hiding a region under a box it has nothing to do with would
    cost you the ability to find it at all.
    """
    budget = max(1, round_max - 1)  # the node itself takes one slot in its round
    queue = [root]
    while queue:
        n = queue.pop(0)
        if len(n.kids) > budget:
            keep, spill = n.kids[:budget], n.kids[budget:]
            n.kids = keep
            for s in spill:
                host = max(keep, key=lambda k: (coverage(s.box, k.box), -_sort_key(k)[0]))
                if coverage(s.box, host.box) >= overlap_min:
                    s.parent = host
                    host.kids.append(s)
                    host.kids.sort(key=_sort_key)
                else:
                    n.kids.append(s)
        queue.extend(n.kids)


def round_set(node: Node, round_min: int = ROUND_MIN, round_max: int = 26) -> list[Node]:
    """The regions to offer under `node`, largest first.

    Its children, plus grandchildren promoted up until the round is as full as one
    keystroke allows. Biggest first, so the coarsest divisions are the ones that get
    subdivided. A promoted child STAYS in the round: promoting its children must not
    cost you the ability to select it.
    """
    # The round drawn on screen is this list PLUS the node itself, and it is the
    # drawn count that decides label width. Budgeting for the offers alone is how
    # a 26-symbol alphabet ended up rendering 27 labels and charging two keystrokes
    # for every single round.
    budget = max(1, round_max - 1)
    out = list(node.kids)
    target = min(round_min or budget, budget)
    expanded: set[int] = set()
    while len(out) < target:
        nxt = next((k for k in out if k.kids and id(k) not in expanded), None)
        if nxt is None:
            break
        expanded.add(id(nxt))
        if len(out) + len(nxt.kids) > budget:
            continue
        out.extend(nxt.kids)
    out.sort(key=_sort_key)
    return out


def label_paths(
    root: Node, symbols: str, round_min: int, round_max: int
) -> list[dict]:
    """Every reachable region with the exact keys that reach it, for evals.

    `path` is what you type; `keystrokes` adds the Return that a region with
    children needs, since selecting one of those opens a round rather than
    capturing. The picker walks the same two functions, so this is the real cost,
    not a model of it.
    """
    rows: list[dict] = []
    seen: set[int] = {id(root)}
    # Breadth-first, so a region promoted into more than one round is recorded at
    # the shallowest one -- the path the user would actually take.
    queue: list[tuple[Node, str, int]] = [(root, "", 0)]
    while queue:
        node, prefix, depth = queue.pop(0)
        offer = round_set(node, round_min, round_max)
        if not offer:
            continue
        # The node itself leads its own round, so it sits at index 0 and can be
        # captured with one more character as well as with Return.
        total = len(offer) + 1
        for i, kid in enumerate(offer):
            if id(kid) in seen:
                continue
            seen.add(id(kid))
            path = prefix + label_for(i + 1, total, symbols)
            rows.append(
                {
                    "geom": kid.box.geom(),
                    "tier": kid.box.tier,
                    "note": kid.box.note,
                    "path": path,
                    "depth": depth + 1,
                    "keystrokes": len(path) + (1 if kid.kids else 0),
                    "round_size": total,
                }
            )
            queue.append((kid, path, depth + 1))
    return rows


# --------------------------------------------------------------------------- #
# The picker
# --------------------------------------------------------------------------- #

RESULT_RE = re.compile(r"^(\d+)x(\d+)\+(-?\d+)\+(-?\d+)\s+\+(-?\d+)\+(-?\d+)")

# Size of a label anchor, in logical px. Big enough that wl-kbptr's font -- which it
# derives from the area's HEIGHT -- lands somewhere readable, and that a two-character
# label fits inside instead of spilling over its neighbours.
ANCHOR_W, ANCHOR_H = 46, 30

# Label height in px, held constant for every element (see the font_size option in
# pick() for why a fixed size is possible at all). 19 fits two characters plus
# padding inside a 46x30 anchor with room to spare.
LABEL_PT = 19

# Overlay palettes.
#
# The colour that matters most is `fill`, and the reason is not aesthetic. wl-kbptr
# paints the label text straight onto the area rectangle with no backing of its own
# (mode_floating.c fills with selectable_bg_color, strokes a 1px border, then
# cairo_show_text on top). So the label's contrast is the contrast of the label
# colour against *whatever was already on screen*, attenuated by the fill's alpha.
# At the old fill alpha of 0x22 -- 13% -- white text over a white article page was
# effectively white on white. Every palette here therefore uses a near-opaque fill,
# which costs nothing: the anchor is only 46x30 logical px, so it hides a
# thumbnail-sized patch of screen and buys a guaranteed contrast ratio.
#
# Colour format is wl-kbptr's own #rrggbbaa (config.c parse_color; 8 digits, alpha
# last). Contrast ratios below are WCAG 2.1 against the fill, computed in
# tests/test_contrast.py rather than asserted here.
THEMES: dict[str, dict[str, str]] = {
    # Dark chip, bright border, white label. Works on both extremes: over a white
    # page the dark chip is the contrast, over a black IDE the bright border and
    # white text are. 17.4:1 label-on-fill.
    # The amber is deliberately dark rather than the obvious bright #ffc857. The
    # typed prefix has to be tellable apart from the untyped remainder -- that is the
    # only cue for how far through a label you are -- and bright amber against white
    # separates by just 1.54:1, which reads as "same colour" at 19px. Darkening it
    # moves the distinction into lightness and takes the separation to 2.4:1.
    "default": {
        "fill": "#0d1117f2",
        "label": "#ffffffff",
        "typed": "#d99a2bff",
        "border": "#7aa2f7ff",
        "dim": "#00000047",
    },
    # Okabe-Ito sky blue for the border, and -- the important part -- the
    # typed-so-far prefix is distinguished from the yet-to-type remainder by
    # LIGHTNESS alone (grey vs white, 4.8:1 between them), never by hue. Nothing in
    # this palette relies on telling two hues apart, so it survives deuteranopia,
    # protanopia and tritanopia identically. Red and green are absent entirely.
    "colorblind": {
        "fill": "#0b0d10f5",
        "label": "#ffffffff",
        "typed": "#9aa0a6ff",
        "border": "#56b4e9ff",
        "dim": "#00000047",
    },
    # Inverse, for anyone who finds dark chips heavy on a light desktop.
    "light": {
        "fill": "#fffffff2",
        "label": "#0b0d10ff",
        "typed": "#5f6368ff",
        "border": "#1a73e8ff",
        "dim": "#ffffff3d",
    },
}


def _anchor_offsets(rings: int) -> list[tuple[int, int]]:
    """Candidate label positions around a box corner, nearest first."""
    out = [(0, 0)]
    for r in range(1, rings + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) == r:
                    out.append((dx * ANCHOR_W, dy * ANCHOR_H))
    return out


def build_anchors(
    boxes: list[Box], mon: Monitor, rings: int = 2
) -> dict[tuple[int, int, int, int], list[Box]]:
    """Give each candidate a readable, non-overlapping label anchor -- grouping when
    the screen genuinely cannot hold one label per candidate.

    wl-kbptr centres each label inside the area it is handed and scales the font from
    that area's height. Handing it the real regions fails in exactly the two ways
    reported: a 27x15 text run gets a label wider than its own box, which spills over
    its neighbours, and concentric boxes share one centre, so their labels stack on the
    same pixels. So the areas passed to wl-kbptr are not the regions -- they are
    fixed-size anchors at each region's top-left corner, like Vimium's link hints.
    Uniform anchor height also means one readable font size for every element, however
    small.

    When a candidate has no free slot near its corner, it is *grouped* onto the anchor
    it would have collided with rather than dropped -- 200 tiny elements in one corner
    cannot each own a readable label, and dropping them would break being able to
    select anything you can see. The caller then offers the group's members in a
    second round, where there is room to spare.

    Returns {anchor geometry -> [candidates reachable through it]}, first is primary.
    """
    placed: list[tuple[int, int, int, int]] = []
    groups: dict[tuple[int, int, int, int], list[Box]] = {}
    offsets = _anchor_offsets(rings)

    def hit(cand: tuple[int, int, int, int]) -> tuple[int, int, int, int] | None:
        cx, cy, cw, ch = cand
        for p in placed:
            px, py, pw, ph = p
            if cx < px + pw and px < cx + cw and cy < py + ph and py < cy + ch:
                return p
        return None

    for b in boxes:
        first_conflict = None
        for dx, dy in offsets:
            x = max(0, min(mon.lg_w - ANCHOR_W, b.x + dx))
            y = max(0, min(mon.lg_h - ANCHOR_H, b.y + dy))
            cand = (x, y, ANCHOR_W, ANCHOR_H)
            clash = hit(cand)
            if clash is None:
                placed.append(cand)
                groups[cand] = [b]
                break
            if first_conflict is None:
                first_conflict = clash
        else:
            groups[first_conflict].append(b)
    return groups



def _label_slots(b: Box, mon: Monitor):
    """Where this region's label may go, best first.

    Its own top-left corner, then ALONG ITS OWN EDGES -- right across the top, then
    down the left side -- and only then out into the spiral around the corner.

    The edges come before the spiral because of what a round of nested regions
    looks like. A message, the message group it is in, and the pane they are both
    in share a top-left corner to within a few pixels, so a spiral search sends
    their labels off on a diagonal into whatever is nearby, and you are left
    reading a clump of labels in the corner with no way to tell which rectangle
    each one belongs to. Sliding along the region's own border instead keeps every
    label touching the thing it names.
    """
    seen: set[tuple[int, int]] = set()

    def slot(x: int, y: int):
        p = (max(0, min(mon.lg_w - ANCHOR_W, x)), max(0, min(mon.lg_h - ANCHOR_H, y)))
        if p in seen:
            return None
        seen.add(p)
        return (p[0], p[1], ANCHOR_W, ANCHOR_H)

    out = []
    for x, y in [(b.x + 1, b.y + 1)]:
        s = slot(x, y)
        if s:
            out.append(s)
    for k in range(1, max(1, b.w // ANCHOR_W)):
        s = slot(b.x + 1 + k * ANCHOR_W, b.y + 1)
        if s:
            out.append(s)
    for k in range(1, max(1, b.h // ANCHOR_H)):
        s = slot(b.x + 1, b.y + 1 + k * ANCHOR_H)
        if s:
            out.append(s)
    for dx, dy in _anchor_offsets(6):
        s = slot(b.x + 1 + dx, b.y + 1 + dy)
        if s:
            out.append(s)
    return out


def build_label_layout(
    boxes: list[Box], mon: Monitor
) -> tuple[list[tuple[Box, tuple[int, int, int, int]]], dict[tuple[int, int, int, int], list[Box]]]:
    """Pair regions with free label rects, grouping any that cannot get their own.

    The region is what wl-kbptr outlines and what it prints back on selection, so
    identity no longer depends on where the label sits -- only legibility does. Labels
    go at each region's top-left rather than its centre, because a centred label on a
    stack of full-width rows lands in a column of blank space belonging to no visible
    outline in particular. Largest region first, so a container claims the corner and
    the nested element steps aside.

    A region that can find no free slot is NOT dropped. Dropping it would leave
    something visibly on screen that cannot be selected, which is a worse failure than
    a crowded label -- it was measured as 7 unreachable candidates before this. Instead
    it is attached to the nearest region that did get a label, and selecting that label
    opens a second round among the few that share it.

    Returns (areas to send, {sent region -> candidates reachable through it}).
    """
    placed: list[tuple[int, int, int, int]] = []
    layout: list[tuple[Box, tuple[int, int, int, int]]] = []
    groups: dict[tuple[int, int, int, int], list[Box]] = {}
    seen: set[tuple[int, int, int, int]] = set()

    def free(r: tuple[int, int, int, int]) -> bool:
        cx, cy, cw, ch = r
        return not any(
            cx < px + pw and px < cx + cw and cy < py + ph and py < cy + ch
            for px, py, pw, ph in placed
        )

    homeless: list[Box] = []
    for b in sorted(boxes, key=lambda b: -b.area):
        key = (b.x, b.y, b.w, b.h)
        if key in seen:
            continue
        seen.add(key)
        for lr in _label_slots(b, mon):
            if free(lr):
                placed.append(lr)
                layout.append((b, lr))
                groups[key] = [b]
                break
        else:
            homeless.append(b)

    # Attach each leftover to the nearest labelled region, by corner distance.
    for b in homeless:
        if not layout:
            break
        host, _ = min(
            layout, key=lambda pair: (pair[0].x - b.x) ** 2 + (pair[0].y - b.y) ** 2
        )
        groups[(host.x, host.y, host.w, host.h)].append(b)
    return layout, groups


def run_round(
    boxes: list[Box],
    mon: Monitor,
    symbols: str,
    timeout: float,
    verbose: bool,
    round_no: int = 1,
    theme: str = "default",
    chips: bool = False,
) -> tuple[str, list[Box], int, int]:
    """Show the labelled overlay once; report what the user did.

    Returns one of:
      ("pick",   [chosen],  monitor_x, monitor_y)   a label was typed
      ("group",  [a, b, …], mx, my)                 that label covers several
                                                    candidates too crowded to each
                                                    get their own
      ("accept", [], mx, my)                        Return
      ("back",   [], mx, my)                        BackSpace at the start
      ("cancel", [], 0, 0)                          Escape, timeout, or a rival
                                                    overlay taking the screen
    """
    # Round two has the screen almost to itself, so let anchors travel further to find
    # a free slot rather than grouping again.
    if chips:
        # Legacy path: hand over displaced chips instead of regions. Only needed with
        # an unpatched wl-kbptr, which ignores the label rect and would centre every
        # label inside its region.
        anchors = build_anchors(boxes, mon, rings=2 if round_no == 1 else 6)
        stdin = "".join(f"{w}x{h}+{x}+{y}\n" for (x, y, w, h) in anchors)
    else:
        layout, anchors = build_label_layout(boxes, mon)
        stdin = "".join(
            f"{b.w}x{b.h}+{b.x}+{b.y} {lr[2]}x{lr[3]}+{lr[0]}+{lr[1]}\n"
            for b, lr in layout
        )
    pal = THEMES.get(theme, THEMES["default"])
    cmd = [
        "wl-kbptr",
        "-O",
        mon.name,
        "-p",  # print only; never move the pointer
        "-o", "modes=floating",
        # Not cosmetic, and not optional. Left unset, wl-kbptr derives its home-row
        # labels from the live keymap on every keymap event, and calls exit(1) if a
        # keycode has no UTF-8 representation -- so anything that installs a
        # minimal virtual keymap while the overlay is up (wtype, some IME and
        # autotype tools) kills the picker mid-selection. Setting it explicitly
        # skips that code path entirely. The 11 characters are only consumed by the
        # bisect and split modes, which this tool never enters.
        "-o", "home_row_keys=asdfjkl;qwe",
        "-o", "mode_floating.source=stdin",
        "-o", f"mode_floating.label_symbols={symbols}",
        # `min proportion max`, and the proportion is deliberately 0. wl-kbptr
        # computes height*proportion then clamps into [min, max] (config.c
        # compute_relative_font_size), so a zero proportion pins the size to `min`
        # exactly. That is the whole fix for "the label is too small for me to even
        # see it": the label size no longer depends on the element's size at all.
        "-o", f"mode_floating.label_font_size={LABEL_PT} 0 {LABEL_PT}",
        "-o", f"mode_floating.label_color={pal['label']}",
        "-o", f"mode_floating.label_select_color={pal['typed']}",
        # The label now has its own opaque backing (label_bg_color), so the region
        # fill is free to stay nearly transparent -- the region's content is the
        # thing being identified and must remain visible through it.
        "-o", f"mode_floating.selectable_bg_color="
        f"{pal['fill'] if chips else pal['border'][:7] + '1f'}",
        "-o", f"mode_floating.label_bg_color={'#00000000' if chips else pal['fill']}",
        "-o", f"mode_floating.selectable_border_color={pal['border']}",
        "-o", f"mode_floating.unselectable_bg_color={pal['dim']}",
        "-o", "general.cancellation_status_code=1",
    ]
    log(verbose, "picker:", len(boxes), "candidates")

    # Popen rather than run(), so the child is reachable from a signal handler and
    # from the timeout path. If kbshot is killed while the picker holds the keyboard
    # grab, the grab must die with it -- otherwise the screen is unusable.
    proc = subprocess.Popen(
        cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    def bail(signum, _frame):
        proc.kill()
        raise SystemExit(128 + signum)

    previous = {s: signal.signal(s, bail) for s in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP)}

    # Yield the screen automatically if another screenshot overlay shows up while we
    # hold the keyboard. This is the half of the lock-up that pre-clearing cannot fix:
    # pressing CTRL+Print and *then* Print starts hyprpicker's fullscreen freeze on
    # top of a picker that already owns the keyboard, and the user is left with a
    # covered screen and nowhere for Escape to go. Cancelling ourselves the moment a
    # rival appears means that never happens, with nothing for the user to remember.
    yielded = threading.Event()

    def watch_for_rivals():
        while not stopped.wait(0.2):
            if any(
                subprocess.run(["pgrep", "-x", n], capture_output=True).returncode == 0
                for n in COMPETING_OVERLAYS
            ):
                yielded.set()
                proc.kill()
                return

    stopped = threading.Event()
    watcher = threading.Thread(target=watch_for_rivals, daemon=True)
    watcher.start()

    try:
        try:
            out, err = proc.communicate(input=stdin, timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.communicate()
            log(verbose, f"picker timed out after {timeout}s; killed it")
            notify(
                "kbshot",
                f"Picker gave up after {timeout}s and released the keyboard.",
                urgency="critical",
            )
            return "cancel", [], 0, 0
    finally:
        stopped.set()
        for s, handler in previous.items():
            signal.signal(s, handler)
        if proc.poll() is None:
            proc.kill()

    if yielded.is_set():
        log(verbose, "another screenshot overlay appeared; yielded the keyboard")
        return "cancel", [], 0, 0

    if proc.returncode != 0 or not out.strip():
        log(verbose, "cancelled", err.strip()[:200])
        return "cancel", [], 0, 0
    # The patched wl-kbptr reports Return and BackSpace-past-the-start as words
    # rather than geometries: floating mode has no notion of the drill-down those
    # keys mean, so it can only say which key was pressed and leave the rest here.
    word = out.strip().splitlines()[0].strip()
    if word in ("ACCEPT", "BACK"):
        log(verbose, f"picker reported {word}")
        return word.lower(), [], mon.x, mon.y
    m = RESULT_RE.match(out.strip())
    if not m:
        log(verbose, "unparseable result:", out.strip())
        return "cancel", [], 0, 0
    w, h, x, y, ox, oy = (int(g) for g in m.groups())
    group = anchors.get((x, y, w, h))
    if not group:
        log(verbose, f"no region maps to anchor {w}x{h}+{x}+{y}")
        return "cancel", [], 0, 0

    if len(group) > 1:
        log(verbose, f"anchor holds {len(group)} candidates")
        return "group", sorted(group, key=lambda b: -b.area), ox, oy

    log(verbose, f"anchor {w}x{h}+{x}+{y} -> {group[0].tier} {group[0].geom()}")
    return "pick", [group[0]], ox, oy


def pick(
    boxes: list[Box],
    mon: Monitor,
    symbols: str,
    timeout: float,
    verbose: bool,
    round_no: int = 1,
    theme: str = "default",
    chips: bool = False,
) -> tuple[int, int, int, int] | None:
    """Flat picker: every candidate at once. `--flat` keeps this reachable.

    Runs a second round when the chosen label covers a group of candidates that were
    too crowded to each get their own label. Round two shows only that handful, so the
    labels have all the room they need -- the user just types a couple more characters.
    """
    kind, got, ox, oy = run_round(
        boxes, mon, symbols, timeout, verbose, round_no, theme, chips
    )
    if kind in ("cancel", "back"):
        return None
    if kind == "accept":
        # Nothing narrower has been chosen, so Return means the whole output.
        return mon.x, mon.y, mon.lg_w, mon.lg_h
    if kind == "group" and round_no < 3:
        notify(
            "kbshot",
            f"{len(got)} overlapping items here — pick again (largest first)",
            urgency="low",
        )
        return pick(got, mon, symbols, timeout, verbose, round_no + 1, theme, chips)
    target = got[0]
    return target.x + ox, target.y + oy, target.w, target.h


def pick_tree(
    root: Node,
    mon: Monitor,
    symbols: str,
    timeout: float,
    verbose: bool,
    theme: str = "default",
    chips: bool = False,
    round_min: int = ROUND_MIN,
    round_max: int | None = None,
) -> tuple[int, int, int, int] | None:
    """Walk the region tree one round at a time; return the captured region.

    Each round offers the current region plus what lives inside it, biggest first.
    A letter descends; Return captures what you already have; BackSpace goes back up
    a level. A region with nothing inside it is captured the moment it is chosen,
    because a round with no choices in it would be a keystroke asking nothing.
    """
    round_max = round_max or one_keystroke_max(symbols)
    path: list[Node] = [root]
    while True:
        node = path[-1]
        here = (node.box.x, node.box.y, node.box.w, node.box.h)
        offer = [k for k in round_set(node, round_min, round_max)
                 if (k.box.x, k.box.y, k.box.w, k.box.h) != here]
        if not offer:
            return node.box.x + mon.x, node.box.y + mon.y, node.box.w, node.box.h

        # The current region leads its own round: outlined, labelled, and pickable.
        # Without it the overlay would show you the choices but not the thing they
        # are choices *within*, and there would be no way to see what Return does.
        by_geom = {(k.box.x, k.box.y, k.box.w, k.box.h): k for k in offer}
        items = [node.box] + [k.box for k in offer]
        log(verbose, f"round at depth {len(path) - 1}: {len(items)} regions")

        kind, got, ox, oy = run_round(
            items, mon, symbols, timeout, verbose, len(path), theme, chips
        )
        if kind == "cancel":
            return None
        if kind == "accept":
            return node.box.x + ox, node.box.y + oy, node.box.w, node.box.h
        if kind == "back":
            if len(path) > 1:
                path.pop()
                continue
            return None
        if kind == "group":
            # Labels too crowded to separate. Ask among just those, which is the same
            # question one level down, so it reuses the same round machinery.
            kind, got, ox, oy = run_round(
                got, mon, symbols, timeout, verbose, len(path) + 1, theme, chips
            )
            if kind != "pick":
                return None
        chosen = got[0]
        key = (chosen.x, chosen.y, chosen.w, chosen.h)
        if key == here:
            return node.box.x + ox, node.box.y + oy, node.box.w, node.box.h
        nxt = by_geom.get(key)
        if nxt is None:
            log(verbose, f"chosen region {chosen.geom()} is not in this round")
            return chosen.x + ox, chosen.y + oy, chosen.w, chosen.h
        if not nxt.kids:
            return nxt.box.x + ox, nxt.box.y + oy, nxt.box.w, nxt.box.h
        path.append(nxt)


# --------------------------------------------------------------------------- #
# Output
# --------------------------------------------------------------------------- #


def crop_native(frame: Path, mon: Monitor, region: tuple[int, int, int, int], dest: Path) -> None:
    """Cut the chosen region out of the already-captured frame, at full pixel res.

    Cropping the frozen frame rather than re-running grim keeps freeze semantics:
    the saved image is the screen as it was when the hotkey fired, and it cannot
    catch the overlay's fade-out animation on the way down.
    """
    gx, gy, w, h = region
    s = mon.scale
    lx, ly = gx - mon.x, gy - mon.y
    # Round each EDGE from its absolute logical coordinate, never the width and
    # height on their own. Rounding the size independently lets the two errors
    # disagree: a 27x26 box at +878+110 on a 4/3 display gives round(26*4/3) = 35
    # rows measured from a top edge that was itself rounded down, one row more than
    # the region actually spans. Edge-rounding also makes adjacent boxes tile
    # exactly, with no seams or overlaps.
    left = max(0, round(lx * s))
    top = max(0, round(ly * s))
    right = min(mon.px_w, round((lx + w) * s))
    bottom = min(mon.px_h, round((ly + h) * s))
    Image.open(frame).crop((left, top, right, bottom)).save(dest)


def copy_image(path: Path) -> None:
    with path.open("rb") as fh:
        subprocess.run(["wl-copy", "-t", "image/png"], stdin=fh, check=False)


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="kbshot",
        description="Screenshot an object on screen, picked with the keyboard.",
    )
    ap.add_argument(
        "--abort",
        action="store_true",
        help="kill any screenshot overlay holding the screen or keyboard, and exit",
    )
    ap.add_argument(
        "--timeout",
        type=float,
        default=PICKER_TIMEOUT_S,
        help=f"seconds before the picker gives up and releases the keyboard (default {PICKER_TIMEOUT_S})",
    )
    ap.add_argument("-o", "--output", help="capture this output instead of the focused one")
    ap.add_argument(
        "-s",
        "--sources",
        default="windows,text,rects,xycut,bands",
        help="comma-separated: windows,text,rects,xycut,bands (default: all)",
    )
    ap.add_argument(
        "--fast",
        action="store_true",
        help="skip OCR (windows, rectangles and whitespace regions only): "
        "~0.5s to the overlay instead of ~1.8s",
    )
    ap.add_argument(
        "--all",
        action="store_true",
        help="offer every granularity, including single lines and tight sub-rectangles, "
        "not just whole objects",
    )
    ap.add_argument("--words", action="store_true", help="also offer individual words")
    ap.add_argument(
        "--corners",
        action="store_true",
        help="skip object detection: type two corners on a narrowing grid instead",
    )
    ap.add_argument(
        "--flat",
        action="store_true",
        help="offer every candidate in one round, as before the hierarchy: no "
        "drilling down, but no relationship between the labels either",
    )
    ap.add_argument(
        "--round-min",
        type=int,
        default=ROUND_MIN,
        help="promote nested regions up until a round offers this many "
        "(default 0: fill every round to --round-max, which is what keeps the "
        "tree shallow)",
    )
    ap.add_argument(
        "--round-max",
        type=int,
        default=0,
        help="most regions to draw in one round, the current one included "
        "(default: the largest round wl-kbptr still labels with one character)",
    )
    ap.add_argument(
        "--contain",
        type=float,
        default=CONTAIN_MIN,
        help=f"fraction of a region that must sit inside a bigger one for that "
        f"bigger one to be its parent (default {CONTAIN_MIN})",
    )
    ap.add_argument(
        "--min-size",
        default="34x20",
        metavar="WxH",
        help="drop candidates smaller than this, in logical px (default 34x20)",
    )
    ap.add_argument(
        "--max",
        type=int,
        default=280,
        help="candidate box budget (default 280, the measured knee: 82%% of primary "
        "regions reachable at IoU 0.7 with mean 1.99 keystrokes and chips covering "
        "7.4%% of the screen; 324 buys 2 more points of recall but costs 2.54 "
        "keystrokes and a visibly carpeted overlay)",
    )
    ap.add_argument(
        "--dedupe-iou",
        type=float,
        default=0.88,
        help="drop a candidate overlapping a kept one by more than this (default 0.82)",
    )
    ap.add_argument(
        "--labels",
        default=LABEL_SYMBOLS,
        metavar="CHARS",
        help=f"label alphabet, easiest key first (default {LABEL_SYMBOLS!r}, tuned for Dvorak)",
    )
    ap.add_argument(
        "--chips",
        action="store_true",
        help="label displaced corner chips instead of outlining the regions "
        "themselves; only needed with an unpatched wl-kbptr, which cannot draw a "
        "label outside its area",
    )
    ap.add_argument(
        "--theme",
        default=os.environ.get("KBSHOT_THEME", "default"),
        choices=sorted(THEMES),
        help="overlay palette; 'colorblind' distinguishes states by lightness only, "
        "never hue (default: default, or $KBSHOT_THEME)",
    )
    ap.add_argument(
        "--ocr", action="store_true", help="OCR the chosen region and copy text instead of the image"
    )
    ap.add_argument(
        "--region", action="store_true", help="print 'X,Y WxH' and exit; capture nothing"
    )
    ap.add_argument("--no-copy", action="store_true", help="save only, leave the clipboard alone")
    ap.add_argument("--no-save", action="store_true", help="clipboard only, write no file")
    ap.add_argument(
        "--ocr-scale",
        type=float,
        default=0.5,
        help="downscale factor for OCR input (default 0.5; 1.0 = native)",
    )
    ap.add_argument(
        "--detect-width",
        type=int,
        default=1440,
        help="width in px to run rectangle detection at (default 1440)",
    )
    ap.add_argument(
        "--from-image",
        metavar="PNG",
        help="run detection on this image instead of the screen (for evals); "
        "never shows a picker, touches the clipboard, or saves a file",
    )
    ap.add_argument(
        "--assume-scale",
        type=float,
        default=1.0,
        help="output scale to assume with --from-image (default 1.0: logical == pixels)",
    )
    ap.add_argument("--debug-overlay", metavar="PNG", help="dump the boxes onto an image and exit")
    ap.add_argument("--debug-json", action="store_true", help="print candidate boxes as JSON and exit")
    ap.add_argument("--debug-frame", metavar="PNG", help="keep the raw capture at this path")
    ap.add_argument(
        "--dump-candidates",
        metavar="JSON",
        help="write the offered boxes and their labels here just before showing the picker",
    )
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    v = args.verbose
    round_max = args.round_max or one_keystroke_max(args.labels)
    if args.abort:
        return abort(v)

    # --from-image is always a dry run: no lock, no overlay, no clipboard, no file.
    # Anything else would make running the eval suite destructive to a live session.
    if args.from_image and not (args.debug_overlay or args.debug_json):
        args.debug_json = True
    debugging = bool(args.debug_overlay or args.debug_json)
    if not shutil.which("wl-kbptr") and not debugging:
        sys.exit("kbshot: wl-kbptr is not on PATH")

    try:
        min_w, min_h = (int(n) for n in args.min_size.lower().split("x", 1))
    except ValueError:
        sys.exit(f"kbshot: --min-size wants WxH, got {args.min_size!r}")

    sources = {s.strip() for s in args.sources.split(",") if s.strip()}
    if args.fast:
        sources.discard("text")
    if args.from_image:
        src_image = Path(args.from_image)
        if not src_image.is_file():
            sys.exit(f"kbshot: no such image {args.from_image!r}")
        mon = synthetic_monitor(src_image, args.assume_scale)
        # There is no compositor behind a static image, so window rects cannot exist.
        sources.discard("windows")
    else:
        src_image = None
        mon = get_monitor(args.output)
    log(v, f"output {mon.name} {mon.px_w}x{mon.px_h}px -> {mon.lg_w}x{mon.lg_h}lg @ {mon.scale:.6f}")

    # An ExitStack rather than a `with` block, purely to avoid re-indenting the whole
    # capture flow. The guards are skipped for the debug modes, which never put an
    # overlay up and so should not tear down a selection the user started by hand.
    stack = contextlib.ExitStack()
    if not debugging:
        stack.enter_context(single_flight(v))
        # Clear rivals BEFORE capturing, not just before the picker: hyprpicker's
        # freeze layer covers the screen, so grim would otherwise bake that frozen
        # copy into the frame and every detected box would describe stale pixels.
        if clear_competing_overlays(v):
            time.sleep(0.25)

    tmpdir = Path(tempfile.mkdtemp(prefix="kbshot-"))
    frame = tmpdir / "frame.png"
    try:
        t0 = time.monotonic()
        if src_image is not None:
            # Copied rather than read in place: source_text writes its downscaled OCR
            # input next to the frame, and an eval must not litter the corpus dir.
            shutil.copyfile(src_image, frame)
            log(v, f"loaded {src_image} {mon.px_w}x{mon.px_h}px")
        else:
            run(["grim", "-o", mon.name, str(frame)])
            log(v, f"captured in {time.monotonic() - t0:.2f}s")

        boxes: list[Box] = []
        if args.corners:
            # Corner mode needs no candidates; the user types the rectangle instead.
            sources = set()
        else:
            boxes = [Box(0, 0, mon.lg_w, mon.lg_h, "window", "whole screen")]

        # Text and rect detection are both CPU-bound and independent; overlapping
        # them keeps the wait close to the slower of the two rather than the sum.
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            futures = {}
            if "text" in sources:
                futures["text"] = pool.submit(
                    source_text, frame, mon.scale, args.ocr_scale, v
                )
            if "rects" in sources:
                futures["rects"] = pool.submit(
                    source_rects, frame, mon.scale, args.detect_width, v
                )
            # Window rects first: source_xycut needs them as seeds, and they are
            # free (a hyprctl call), so this costs nothing but ordering.
            if "windows" in sources:
                boxes += source_windows(mon)
            win_seeds = [b for b in boxes if b.tier == "window"]
            if "xycut" in sources:
                futures["xycut"] = pool.submit(
                    source_xycut, frame, mon.scale, args.detect_width, v, win_seeds
                )
            if "bands" in sources:
                futures["bands"] = pool.submit(
                    source_bands, frame, mon.scale, args.detect_width, v, win_seeds
                )
            for name, fut in futures.items():
                try:
                    boxes += fut.result()
                except Exception as exc:  # a bad source must not kill the picker
                    log(v, f"source {name} failed: {exc!r}")

        if not args.words:
            boxes = [b for b in boxes if b.tier != "word"]

        if not args.all:
            boxes = [b for b in boxes if b.tier in OBJECT_TIERS]
        boxes = clip_to_output(boxes, mon, min_w, min_h)
        log(v, f"{len(boxes)} raw candidates in {time.monotonic() - t0:.2f}s")
        boxes = dedupe(boxes, args.dedupe_iou)
        log(v, f"{len(boxes)} after dedupe")
        boxes = apply_budget(boxes, args.max)
        # Reading order, so the labels feel spatially predictable.
        boxes.sort(key=lambda b: (b.y, b.x))
        log(v, f"{len(boxes)} offered, ready in {time.monotonic() - t0:.2f}s")

        if args.debug_frame:
            shutil.copyfile(frame, args.debug_frame)
        # Dumped before the debug returns so an eval can read the *labels and anchor
        # groups the user would actually be shown* -- the box list alone cannot tell
        # you how many keystrokes a region costs, which is half of whether the UI is
        # any good.
        if args.dump_candidates:
            # Must mirror whichever layout the picker will actually use, or an eval
            # measures label overlap and keystroke cost for a layout that is not the
            # one being rendered.
            if not args.flat and not args.corners:
                root = build_hierarchy(
                    boxes, mon, args.contain, OVERLAP_MIN, round_max
                )
                # Rounds are drawn one at a time, so the invariant a layout has to
                # satisfy -- no two labels on top of each other -- is per round, and
                # the dump has to be per round for an eval to check it.
                rounds = []
                for node in root.walk():
                    offer = round_set(node, args.round_min, round_max)
                    if not offer:
                        continue
                    layout, _ = build_label_layout(
                        [node.box] + [k.box for k in offer], mon
                    )
                    rounds.append(
                        {
                            "of": node.box.geom(),
                            # Both counts, because they differ exactly when a round
                            # was too crowded for one label each and the picker has
                            # to ask a follow-up question that label_paths does not
                            # model. An eval that only saw `items` could not tell.
                            "offered": len(offer) + 1,
                            "items": [
                                {
                                    "label": label_for(i, len(layout), args.labels),
                                    "region": b.geom(),
                                    "anchor": f"{lr[2]}x{lr[3]}+{lr[0]}+{lr[1]}",
                                }
                                for i, (b, lr) in enumerate(layout)
                            ],
                        }
                    )
                dump = {
                    "mode": "tree",
                    "root": root.box.geom(),
                    "regions": label_paths(
                        root, args.labels, args.round_min, round_max
                    ),
                    "rounds": rounds,
                }
            elif args.chips:
                groups = build_anchors(boxes, mon)
                dump = [
                    {
                        "i": i,
                        "label": label_for(i, len(groups), args.labels),
                        "anchor": f"{a[2]}x{a[3]}+{a[0]}+{a[1]}",
                        "members": [
                            {"geom": m.geom(), "tier": m.tier, "note": m.note}
                            for m in members
                        ],
                    }
                    for i, (a, members) in enumerate(groups.items())
                ]
            else:
                layout, groups = build_label_layout(boxes, mon)
                dump = [
                    {
                        "i": i,
                        "label": label_for(i, len(layout), args.labels),
                        "anchor": f"{lr[2]}x{lr[3]}+{lr[0]}+{lr[1]}",
                        "region": b.geom(),
                        "members": [
                            {"geom": m.geom(), "tier": m.tier, "note": m.note}
                            for m in groups[(b.x, b.y, b.w, b.h)]
                        ],
                    }
                    for i, (b, lr) in enumerate(layout)
                ]
            Path(args.dump_candidates).write_text(json.dumps(dump, indent=1))
        if args.debug_json:
            print(
                json.dumps(
                    [
                        {
                            "i": i,
                            # Only meaningful with --flat: a hierarchical run labels
                            # per round, so a candidate's cost is a path, and that
                            # lives in --dump-candidates.
                            "label": label_for(i, len(boxes), args.labels)
                            if args.flat
                            else None,
                            "geom": b.geom(),
                            "tier": b.tier,
                            "note": b.note,
                        }
                        for i, b in enumerate(boxes)
                    ],
                    indent=1,
                )
            )
            return 0
        if args.debug_overlay:
            draw_debug(frame, boxes, mon, Path(args.debug_overlay))
            print(f"wrote {args.debug_overlay} with {len(boxes)} boxes")
            return 0

        if not boxes and not args.corners:
            notify("kbshot", "Nothing detected on screen", urgency="critical")
            return 1

        if args.corners:
            region = pick_corners(mon, args.timeout, v, theme=args.theme)
        elif args.flat:
            region = pick(boxes, mon, args.labels, args.timeout, v, theme=args.theme,
                          chips=args.chips)
        else:
            root = build_hierarchy(boxes, mon, args.contain, OVERLAP_MIN, round_max)
            region = pick_tree(root, mon, args.labels, args.timeout, v,
                               theme=args.theme, chips=args.chips,
                               round_min=args.round_min, round_max=round_max)
        if region is None:
            return 1
        gx, gy, w, h = region
        log(v, f"chose {w}x{h}+{gx}+{gy} (global logical)")

        if args.region:
            print(f"{gx},{gy} {w}x{h}")
            return 0

        shot = tmpdir / "shot.png"
        crop_native(frame, mon, region, shot)

        stamp = datetime.now().strftime("%Y-%m-%d-%Hh%Mm%Ss")
        if args.ocr:
            text = subprocess.run(
                ["tesseract", str(shot), "-", "--psm", "6"],
                capture_output=True,
                text=True,
                check=False,
                env=dict(os.environ, OMP_THREAD_LIMIT="1"),
            ).stdout
            text = "\n".join(ln for ln in text.splitlines() if ln.strip())
            if not args.no_copy:
                subprocess.run(["wl-copy"], input=text.encode(), check=False)
            if not args.no_save:
                SAVE_DIR.mkdir(parents=True, exist_ok=True)
                (SAVE_DIR / f"{stamp}.txt").write_text(text)
            preview = text[:120].replace("\n", " ")
            notify("kbshot: text copied", preview or "(no text found)")
            print(text)
            return 0

        dest = shot
        if not args.no_save:
            SAVE_DIR.mkdir(parents=True, exist_ok=True)
            dest = SAVE_DIR / f"{stamp}.png"
            shutil.copyfile(shot, dest)
        if not args.no_copy:
            copy_image(shot)
        with Image.open(shot) as im:
            dims = f"{im.width}x{im.height}"
        # Say WHICH region was captured, not just that something was. With nested
        # elements the label alone does not tell you whether you got the inner box or
        # its container, so state the kind and the logical geometry and attach the
        # image itself as the notification icon.
        gx, gy, gw, gh = region
        what = f"{gw}x{gh} at {gx},{gy}"
        notify("kbshot: copied", f"{what} ({dims} px)\n{dest}", icon=str(dest))
        print(dest)
        return 0
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
        stack.close()


def draw_debug(frame: Path, boxes: list[Box], mon: Monitor, dest: Path) -> None:
    """Render the candidate boxes over the capture, for eyeballing detection quality."""
    from PIL import ImageDraw

    colours = {
        "window": (255, 80, 80),
        "block": (80, 255, 120),
        "para": (120, 200, 255),
        "line": (255, 220, 80),
        "rect-loose": (255, 120, 255),
        "rect-tight": (140, 140, 255),
        "word": (200, 200, 200),
    }
    img = Image.open(frame).convert("RGB")
    d = ImageDraw.Draw(img)
    s = mon.scale
    for i, b in enumerate(boxes):
        c = colours.get(b.tier, (255, 255, 255))
        d.rectangle([b.x * s, b.y * s, (b.x + b.w) * s, (b.y + b.h) * s], outline=c, width=2)
        label = LABEL_SYMBOLS[i] if i < len(LABEL_SYMBOLS) else str(i)
        d.text((b.x * s + 3, b.y * s + 1), f"{label}:{b.tier}", fill=c)
    img.save(dest)


if __name__ == "__main__":
    sys.exit(main())
