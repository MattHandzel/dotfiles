#!/usr/bin/env python3
"""Drive a real drill-down: kbshot's pick_tree against the real patched picker.

The unit tests score the tree; e2e_picker.sh scores the keys. Neither says the
two are wired together -- that a letter typed in round one really opens round
two on that region's contents, that Return really captures what you already have
rather than the thing under the cursor, that BackSpace really goes back up.

Run from e2e_drilldown.sh, which supplies a nested headless compositor. Never run
this against a live session: the picker takes an exclusive keyboard grab.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import kbshot  # noqa: E402
from kbshot import Box, Monitor, build_hierarchy, label_for, round_set  # noqa: E402

OUT = os.environ.get("E2E_OUTPUT", "HEADLESS-1")
W = int(os.environ.get("E2E_W", "1280"))
H = int(os.environ.get("E2E_H", "720"))
SYMS = "udagcprfylmwkjvbxq"

FAILURES: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"  {'PASS' if ok else 'FAIL'}  {name}{'  -- ' + detail if detail else ''}",
          flush=True)
    if not ok:
        FAILURES.append(name)


def mon() -> Monitor:
    return Monitor(OUT, 0, 0, 0, W, H, W, H, 1.0, 1, -1)


def scene() -> list[Box]:
    """Two panes; the left one holds three cards; the top card holds two lines.

    Small enough that the whole tree fits in one round-max, so the keystroke for
    each step is computable by hand below rather than read back out of the code
    under test.
    """
    return [
        Box(0, 0, 600, 700, "xy-pane", "left pane"),
        Box(640, 0, 620, 700, "xy-pane", "right pane"),
        Box(20, 20, 560, 200, "block", "card A"),
        Box(20, 240, 560, 200, "block", "card B"),
        Box(20, 460, 560, 200, "block", "card C"),
        Box(30, 30, 540, 80, "para", "line A1"),
        Box(30, 120, 540, 80, "para", "line A2"),
    ]


def typist(keys: list[str], tries: int = 12) -> threading.Thread:
    """Send one key per round, retrying until that round's picker actually exits.

    A single well-timed send is a coin flip and was measured as one: the key is
    dropped if it lands before the layer surface has taken its keyboard grab, and
    different checks failed on different runs. Retrying until the process is gone
    is what makes the result mean something. Safe to repeat, because every round
    here is one character wide, so a duplicate arrives after the picker has
    already exited and goes nowhere.
    """

    def seen() -> set[int]:
        p = subprocess.run(["pgrep", "-x", "-u", str(os.getuid()), "wl-kbptr"],
                           capture_output=True, text=True)
        return {int(x) for x in p.stdout.split()}

    def gone(pid: int, wait: float) -> bool:
        deadline = time.monotonic() + wait
        while time.monotonic() < deadline:
            if not Path(f"/proc/{pid}").exists():
                return True
            time.sleep(0.05)
        return not Path(f"/proc/{pid}").exists()

    def run() -> None:
        served: set[int] = set()
        for key in keys:
            pid = None
            for _ in range(300):
                if stop.is_set():
                    return
                fresh = seen() - served
                if fresh:
                    pid = min(fresh)
                    break
                time.sleep(0.05)
            if pid is None:
                print(f"  (typist: no picker appeared for {key!r})", flush=True)
                return
            served.add(pid)
            args = ["wtype", "-k", key] if len(key) > 1 else ["wtype", "--", key]
            time.sleep(0.6)
            for _ in range(tries):
                if stop.is_set():
                    return
                subprocess.run(args, capture_output=True)
                if gone(pid, 0.7):
                    break
            else:
                print(f"  (typist: {key!r} never took after {tries} tries)", flush=True)
                return

    stop = threading.Event()
    t = threading.Thread(target=run, daemon=True)
    t.stop = stop  # type: ignore[attr-defined]
    t.start()
    return t


def drill(keys: list[str]) -> tuple[int, int, int, int] | None:
    m = mon()
    root = build_hierarchy(scene(), m, round_max=kbshot.one_keystroke_max(SYMS))
    t = typist(keys)
    try:
        return kbshot.pick_tree(root, m, SYMS, timeout=40, verbose=False,
                                round_max=kbshot.one_keystroke_max(SYMS))
    finally:
        # A typist still waiting for a round that never came would otherwise pick
        # up the NEXT case's picker and type into it. That is what made the Escape
        # check come back with a captured region instead of a cancellation on two
        # runs out of three -- a stale Return from the case before it.
        t.stop.set()  # type: ignore[attr-defined]
        t.join(timeout=5)


def key_for(node, target_geom: str) -> str | None:
    """The character that selects `target_geom` in `node`'s round."""
    offer = round_set(node, 0, kbshot.one_keystroke_max(SYMS))
    for i, k in enumerate(offer):
        if k.box.geom() == target_geom:
            return label_for(i + 1, len(offer) + 1, SYMS)
    return None


def main() -> int:
    m = mon()
    root = build_hierarchy(scene(), m, round_max=kbshot.one_keystroke_max(SYMS))
    left = next(n for n in root.walk() if n.box.note == "left pane")
    card_a = next(n for n in root.walk() if n.box.note == "card A")

    k_left = key_for(root, left.box.geom())
    k_card = key_for(left, card_a.box.geom())
    k_line = key_for(card_a, "540x80+30+30")
    print(f"  (round 1 key for the left pane: {k_left!r}; "
          f"its round's key for card A: {k_card!r}; card A's key for line A1: {k_line!r})",
          flush=True)
    if not (k_left and k_card and k_line):
        print("  FAIL  could not compute the keys to type")
        return 1

    print("\ndrill-down through the real picker:", flush=True)

    got = drill([k_left, k_card, k_line])
    check(
        "letter, letter, letter reaches the region three rounds down",
        got == (30, 30, 540, 80),
        f"got {got}, wanted (30, 30, 540, 80)",
    )

    got = drill([k_left, k_card, "Return"])
    check(
        "Return captures the region already selected, not one inside it",
        got == (20, 20, 560, 200),
        f"got {got}, wanted card A (20, 20, 560, 200)",
    )

    got = drill([k_left, "Return"])
    check(
        "Return one round earlier captures the bigger region",
        got == (0, 0, 600, 700),
        f"got {got}, wanted the left pane (0, 0, 600, 700)",
    )

    # BackSpace at the start of round 3 goes back to round 2, where the next
    # letter picks a DIFFERENT card -- so this lands somewhere the same key
    # sequence without the BackSpace could not.
    k_card_c = key_for(left, "560x200+20+460")
    got = drill([k_left, k_card, "BackSpace", k_card_c, "Return"])
    check(
        "BackSpace goes back up a level instead of cancelling",
        got == (20, 460, 560, 200),
        f"got {got}, wanted card C (20, 460, 560, 200)",
    )

    got = drill(["Escape"])
    check(
        "Escape still cancels the whole thing (control)",
        got is None,
        f"got {got}, wanted None",
    )

    print()
    if FAILURES:
        print(f"FAIL: {len(FAILURES)} check(s): {FAILURES}")
        return 1
    print("PASS: the drill-down works against the real picker")
    return 0


if __name__ == "__main__":
    sys.exit(main())
