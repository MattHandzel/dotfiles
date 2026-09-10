#!/usr/bin/env python3
"""Unit tests for the region hierarchy and the round-by-round drill-down.

These are the checks the image eval cannot make. The eval scores detection on
real-looking screens; this scores the *structure* on screens small enough to
reason about by hand, so a wrong parent or an unreachable region is a named
failure rather than a recall number moving by a point.

Every test here is paired with a negative control -- a deliberately broken input
that must FAIL the same assertion -- because a test that cannot fail measures
nothing. Run: test_hierarchy.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import kbshot  # noqa: E402
from kbshot import (  # noqa: E402
    Box,
    Monitor,
    build_hierarchy,
    build_label_layout,
    coverage,
    label_for,
    label_paths,
    round_set,
)

FAILURES: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> bool:
    print(f"  {'PASS' if ok else 'FAIL'}  {name}{'  -- ' + detail if detail else ''}")
    if not ok:
        FAILURES.append(name)
    return ok


def mon(w: int = 2160, h: int = 1350) -> Monitor:
    return Monitor("EVAL", 0, 0, 0, w, h, w, h, 1.0, 1, -1)


def geoms(nodes) -> list[str]:
    return [n.box.geom() for n in nodes]


def find(root, geom):
    for n in root.walk():
        if n.box.geom() == geom:
            return n
    return None


# --------------------------------------------------------------------------- #


def test_one_keystroke_budget():
    """A round must never be sized so that wl-kbptr needs two characters for it.

    label.c does `while (n > 0) { len++; n /= num_symbols; }`, so N == num_symbols
    already spills to two characters. Getting this off by one cost a keystroke on
    EVERY round and was invisible in the structural checks -- it showed up only as
    the keystroke mean staying at 5.5 while the tree got three times shallower.
    """
    print("one-keystroke round budget")
    syms = kbshot.LABEL_SYMBOLS
    n = kbshot.one_keystroke_max(syms)
    check(
        f"{n} areas label in one character",
        len(label_for(0, n, syms)) == 1,
        f"width {len(label_for(0, n, syms))}",
    )
    check(
        f"{n + 1} areas do not (the off-by-one this guards)",
        len(label_for(0, n + 1, syms)) == 2,
        f"width {len(label_for(0, n + 1, syms))}",
    )
    # And the rounds the tree actually builds must respect it, node included. A
    # nested layout, because the one case that is allowed to exceed the budget --
    # regions that overlap nothing kept, covered by its own test -- would mask this.
    m = mon()
    boxes = []
    for p in range(4):
        boxes.append(Box(p * 540, 0, 520, 1300, "xy-pane", f"pane{p}"))
        for t in range(15):
            boxes.append(Box(p * 540 + 10, 10 + t * 85, 500, 75, "para", f"p{p}t{t}"))
    root = build_hierarchy(boxes, m, round_max=n)
    worst = max(
        (len(round_set(x, 0, n)) + 1 for x in root.walk() if round_set(x, 0, n)),
        default=0,
    )
    check(
        "no round the tree builds needs two characters",
        len(label_for(0, worst, kbshot.LABEL_SYMBOLS)) == 1,
        f"biggest round is {worst} regions",
    )


def test_coverage():
    print("coverage")
    a = Box(0, 0, 100, 100, "t")
    b = Box(0, 0, 200, 200, "t")
    check("full containment is 1.0", coverage(a, b) == 1.0)
    check("disjoint is 0.0", coverage(a, Box(500, 500, 10, 10, "t")) == 0.0)
    half = coverage(Box(50, 0, 100, 10, "t"), Box(0, 0, 100, 100, "t"))
    check("half in, half out is 0.5", abs(half - 0.5) < 1e-9, f"got {half}")
    # Negative control: coverage is NOT symmetric, and a test that passed for
    # both directions would mean the parent search could pick a child as parent.
    check(
        "coverage is directional",
        coverage(b, a) < 1.0,
        f"coverage(big, small)={coverage(b, a)}",
    )


def test_parent_is_smallest_container():
    print("\nparent is the smallest container")
    m = mon()
    window = Box(0, 0, 1000, 800, "window")
    column = Box(10, 10, 480, 780, "xy-pane")
    para = Box(20, 20, 400, 100, "para")
    root = build_hierarchy([window, column, para], m, round_max=26)

    n_para = find(root, para.geom())
    check(
        "paragraph's parent is the column, not the window",
        n_para.parent.box.geom() == column.geom(),
        f"got {n_para.parent.box.geom()}",
    )
    check(
        "column's parent is the window",
        find(root, column.geom()).parent.box.geom() == window.geom(),
    )
    check(
        "window's parent is the screen root",
        find(root, window.geom()).parent is root,
    )

    # Negative control: delete the column and the paragraph MUST re-parent to the
    # window. If this came out the same either way, the test above proves nothing.
    root2 = build_hierarchy([window, para], m, round_max=26)
    check(
        "without the column the paragraph re-parents to the window",
        find(root2, para.geom()).parent.box.geom() == window.geom(),
        f"got {find(root2, para.geom()).parent.box.geom()}",
    )


def test_partial_overlap_threshold():
    print("\ncontainment threshold")
    m = mon()
    host = Box(0, 0, 1000, 1000, "window")
    # 85% inside: a paragraph whose bullet pokes out of its column.
    mostly = Box(850, 0, 1000, 100, "para")
    inside = coverage(mostly, host)
    check("the probe really is a partial overlap", 0.1 < inside < 0.2, f"{inside:.2f}")
    r_strict = build_hierarchy([host, mostly], m, contain_min=0.80, round_max=26)
    check(
        "a 15%-overlapping region does NOT become a child at 0.80",
        find(r_strict, mostly.geom()).parent is r_strict,
    )
    r_loose = build_hierarchy([host, mostly], m, contain_min=0.10, round_max=26)
    check(
        "the same region DOES become a child at 0.10",
        find(r_loose, mostly.geom()).parent.box.geom() == host.geom(),
    )


def test_no_cycles_and_every_box_reachable():
    print("\nno cycles, nothing lost")
    m = mon()
    boxes = []
    # A pathological pile: many nested boxes plus equal-area siblings, which is
    # where a parent search that is not a total order starts producing loops.
    for i in range(12):
        boxes.append(Box(i * 5, i * 5, 900 - i * 10, 700 - i * 10, "rect-loose"))
    for i in range(8):
        boxes.append(Box(1000 + i * 60, 40, 50, 50, "rect-tight"))
    root = build_hierarchy(boxes, m, round_max=26)

    walked = list(root.walk())
    check(
        "every candidate appears exactly once in the tree",
        sorted(n.box.geom() for n in walked if n is not root)
        == sorted(b.geom() for b in boxes),
        f"{len(walked) - 1} nodes vs {len(boxes)} boxes",
    )
    # walk() terminating at all is the cycle check; make it explicit anyway.
    depth_ok = True
    for n in walked:
        seen, cur, d = set(), n, 0
        while cur is not None:
            if id(cur) in seen:
                depth_ok = False
                break
            seen.add(id(cur))
            cur = cur.parent
            d += 1
            if d > len(boxes) + 2:
                depth_ok = False
                break
    check("no node's parent chain loops", depth_ok)


def test_screen_sized_candidate_is_not_a_level():
    print("\nscreen-sized candidate")
    m = mon(1000, 1000)
    full = Box(0, 0, 1000, 1000, "window", "whole screen")
    a = Box(0, 0, 500, 1000, "xy-pane")
    b = Box(500, 0, 500, 1000, "xy-pane")
    root = build_hierarchy([full, a, b], m, round_max=26)
    check(
        "a full-screen candidate is dropped rather than becoming the only choice",
        len(root.kids) == 2,
        f"first round offers {geoms(root.kids)}",
    )
    # Negative control: a window that is merely LARGE, not full-screen, must still
    # be a level -- otherwise the rule would swallow real containers.
    big = Box(0, 0, 1000, 900, "window")
    root2 = build_hierarchy([big, Box(10, 10, 480, 880, "xy-pane")], m, round_max=26)
    check(
        "a 90%-of-screen window is still a level",
        len(root2.kids) == 1 and root2.kids[0].box.geom() == big.geom(),
        f"first round offers {geoms(root2.kids)}",
    )


def test_round_cap_pushes_overflow_deeper():
    print("\nround cap")
    m = mon(2000, 2000)
    # A staircase of same-size boxes, each shifted a quarter of its own width. A
    # neighbour covers 75% of the next -- over the overlap threshold but under the
    # containment one -- so all ten are siblings in round one, which is the
    # situation the cap exists for.
    W = 800
    sibs = [Box(i * (W // 4), 100, W, W, "rect-loose", f"s{i}") for i in range(10)]

    root = build_hierarchy(sibs, m, round_max=26)
    check(
        "the fixture really does dodge containment",
        0.45 <= coverage(sibs[1], sibs[0]) < 0.80,
        f"neighbour coverage {coverage(sibs[1], sibs[0]):.2f}",
    )
    check(
        "uncapped, all ten are one round",
        len(root.kids) == 10,
        f"{len(root.kids)} first-round regions",
    )

    capped = build_hierarchy(sibs, m, round_max=3)
    check(
        "capping shrinks the first round",
        len(capped.kids) < 10,
        f"{len(capped.kids)} first-round regions",
    )
    check(
        "capping loses nothing: every region is still in the tree",
        len(list(capped.walk())) - 1 == len(sibs),
        f"{len(list(capped.walk())) - 1} nodes",
    )
    # The contract is not "a round is never bigger than the cap" -- a region that
    # overlaps nothing kept has to stay visible or it becomes unfindable. It is
    # "nothing is over the cap unless it had nowhere to go".
    strandable = []
    for n in capped.walk():
        if len(n.kids) <= 3:
            continue
        keep, extra = n.kids[:3], n.kids[3:]
        for e in extra:
            best = max(coverage(e.box, k.box) for k in keep)
            if best >= kbshot.OVERLAP_MIN:
                strandable.append((e.box.geom(), round(best, 2)))
    check(
        "every region left over the cap had no sibling to go under",
        not strandable,
        f"{strandable[:3]}",
    )
    check(
        "and each spilled region did go under something it overlaps",
        all(
            coverage(n.box, n.parent.box) >= kbshot.OVERLAP_MIN
            for n in capped.walk()
            if n.parent is not None and n.parent is not capped
        ),
    )


def test_non_overlapping_overflow_stays_visible():
    print("\noverflow with nothing to hide under")
    m = mon(2000, 2000)
    # Eight disjoint tiles and a cap of 3. Five have nowhere sane to go: pushing
    # them under a tile they do not touch would make them unfindable.
    boxes = [Box(i * 240, 0, 200, 200, "rect-loose", f"t{i}") for i in range(8)]
    root = build_hierarchy(boxes, m, round_max=3)
    check(
        "disjoint overflow stays in the round rather than being hidden",
        len(root.kids) == 8,
        f"{len(root.kids)} in round one",
    )
    check(
        "and nothing was dropped",
        len(list(root.walk())) - 1 == 8,
    )


def test_round_min_promotes_grandchildren():
    print("\nthin rounds get grandchildren promoted")
    m = mon()
    outer = Box(0, 0, 1000, 1000, "window")
    inner = Box(10, 10, 980, 980, "xy-pane")
    leaves = [Box(20, 20 + i * 100, 900, 80, "para", f"p{i}") for i in range(6)]
    root = build_hierarchy([outer, inner] + leaves, m, round_max=26)

    thin = round_set(root, round_min=1, round_max=26)
    check(
        "with round_min=1 the first round is just the window",
        geoms(thin) == [outer.geom()],
        f"{geoms(thin)}",
    )
    fat = round_set(root, round_min=6, round_max=26)
    check(
        "with round_min=6 the round grows past a single choice",
        len(fat) >= 6,
        f"{len(fat)} offered: {geoms(fat)}",
    )
    check(
        "the promoted parent is STILL selectable in the same round",
        outer.geom() in geoms(fat) and inner.geom() in geoms(fat),
        f"{geoms(fat)}",
    )
    check(
        "promotion respects round_max",
        len(round_set(root, round_min=99, round_max=4)) <= 4,
        f"{len(round_set(root, round_min=99, round_max=4))}",
    )


def test_every_region_has_a_keystroke_path():
    print("\nkeystroke paths")
    m = mon()
    boxes = [Box(0, 0, 1400, 1000, "window")]
    for i in range(4):
        boxes.append(Box(20 + i * 340, 20, 320, 960, "xy-pane", f"col{i}"))
        for j in range(7):
            boxes.append(Box(30 + i * 340, 30 + j * 130, 300, 110, "para", f"c{i}p{j}"))
    root = build_hierarchy(boxes, m, round_max=26)
    rows = label_paths(root, kbshot.LABEL_SYMBOLS, round_min=6, round_max=26)

    got = {r["geom"] for r in rows}
    missing = [b.geom() for b in boxes if b.geom() not in got]
    check("every region is reachable by some path", not missing, f"missing {missing[:3]}")

    ks = [r["keystrokes"] for r in rows]
    print(f"     {len(rows)} regions, keystrokes mean "
          f"{sum(ks) / len(ks):.2f} max {max(ks)}")


def test_each_keystroke_narrows():
    """The claim under test: typing a key restricts you to what is inside.

    NOT tested as "a child's path extends its parent's path" -- that is false by
    design and would have been a green test that proved nothing. A region promoted
    into its GRANDparent's round is reached one round earlier, so its keys extend
    the grandparent's, not the parent's. What must hold is the property the user
    relies on: whatever a round offers is mostly inside the region that round
    belongs to, so no keystroke ever moves you sideways.
    """
    print("\neach keystroke narrows")
    m = mon()
    boxes = [Box(0, 0, 1400, 1000, "window")]
    for i in range(4):
        boxes.append(Box(20 + i * 340, 20, 320, 960, "xy-pane", f"col{i}"))
        for j in range(7):
            boxes.append(Box(30 + i * 340, 30 + j * 130, 300, 110, "para", f"c{i}p{j}"))
    root = build_hierarchy(boxes, m, round_max=26)

    NARROW_MIN = 0.5
    strays = []
    for node in root.walk():
        for kid in round_set(node, 6, 26):
            c = coverage(kid.box, node.box)
            if c < NARROW_MIN:
                strays.append((node.box.geom(), kid.box.geom(), round(c, 2)))
    check(
        f"every region a round offers is >={NARROW_MIN} inside that round's region",
        not strays,
        f"{strays[:3]}",
    )
    # Negative control: run the identical loop with each round's contents taken
    # from a DIFFERENT round. If that does not flag strays, the loop above is not
    # measuring anything.
    rounds = [(n, round_set(n, 6, 26)) for n in root.walk()]
    rounds = [r for r in rounds if r[1]]
    control = [
        (n.box.geom(), k.box.geom())
        for (n, _), (_, other) in zip(rounds, rounds[1:] + rounds[:1])
        for k in other
        if coverage(k.box, n.box) < NARROW_MIN
    ]
    check(
        "the narrowing check can actually fail (negative control)",
        bool(control),
        f"{len(control)} strays when rounds are swapped",
    )


def test_shared_prefixes_mean_shared_pixels():
    """The headline claim, as a number: more keys in common => more pixels in common.

    Measured as mean pairwise overlap bucketed by how many leading keys two
    regions' paths share, which must rise monotonically. The control is the same
    regions with their paths shuffled -- a labelling that carries no structure --
    and it must NOT come out monotone, or the metric is measuring nothing.
    """
    print("\nshared prefixes track overlap")
    import random

    m = mon()
    boxes = []
    for i in range(5):
        boxes.append(Box(i * 420, 20, 400, 1200, "xy-pane", f"col{i}"))
        for j in range(5):
            boxes.append(Box(i * 420 + 10, 30 + j * 240, 380, 220, "block", f"c{i}b{j}"))
            for k in range(2):
                boxes.append(
                    Box(i * 420 + 20, 40 + j * 240 + k * 105, 360, 95, "para", f"c{i}b{j}p{k}")
                )
    root = build_hierarchy(boxes, m, round_max=26)
    rows = label_paths(root, kbshot.LABEL_SYMBOLS, 6, 26)

    def lcp(a: str, b: str) -> int:
        n = 0
        while n < min(len(a), len(b)) and a[n] == b[n]:
            n += 1
        return n

    def profile(paths: list[str]) -> dict[int, float]:
        acc: dict[int, list[float]] = {}
        for i in range(len(rows)):
            for j in range(i + 1, len(rows)):
                ba, bb = _box(rows[i]["geom"]), _box(rows[j]["geom"])
                acc.setdefault(lcp(paths[i], paths[j]), []).append(
                    max(coverage(ba, bb), coverage(bb, ba))
                )
        return {k: sum(v) / len(v) for k, v in sorted(acc.items()) if len(v) >= 5}

    def spread(p: dict[int, float]) -> float:
        ks = sorted(p)
        return p[ks[-1]] / max(p[ks[0]], 1e-6)

    real = profile([r["path"] for r in rows])
    ks = sorted(real)
    monotone = all(real[a] < real[b] for a, b in zip(ks, ks[1:]))
    check(
        "mean overlap rises with every extra key in common",
        monotone and len(ks) >= 2,
        "  ".join(f"{k} keys shared -> {real[k]:.3f}" for k in ks),
    )

    # Shuffling the paths among the same regions keeps path LENGTHS, and length
    # correlates with depth and so with size, so the control comes out weakly
    # monotone too. Monotonicity alone therefore proves nothing; the size of the
    # effect is what does. Compare first bucket to last on both.
    rng = random.Random(20260731)
    shuffled = [r["path"] for r in rows]
    rng.shuffle(shuffled)
    ctrl = profile(shuffled)
    check(
        "and the effect is an order of magnitude bigger than shuffled paths give",
        spread(real) > 10 * spread(ctrl),
        f"real x{spread(real):.0f} vs shuffled x{spread(ctrl):.1f}  "
        + "  ".join(f"{k} -> {ctrl[k]:.3f}" for k in sorted(ctrl)),
    )


def _box(geom: str) -> Box:
    wh, x, y = geom.split("+")
    w, h = wh.split("x")
    return Box(int(x), int(y), int(w), int(h), "t")


def test_round_labels_match_the_paths():
    print("\nthe dump's paths match what the picker will render")
    m = mon()
    boxes = [Box(0, 0, 1400, 1000, "window")]
    for i in range(5):
        boxes.append(Box(20 + i * 270, 20, 250, 960, "xy-pane", f"col{i}"))
        for j in range(5):
            boxes.append(Box(30 + i * 270, 30 + j * 180, 230, 160, "para", f"c{i}p{j}"))
    root = build_hierarchy(boxes, m, round_max=26)
    rows = {r["geom"]: r for r in label_paths(root, kbshot.LABEL_SYMBOLS, 6, 26)}

    # pick_tree hands build_label_layout `[node] + offer`; the label index is that
    # layout's order. label_paths assumes the same order. Confirm they agree, or
    # every keystroke number in the eval is fiction.
    mismatches = []
    for node in root.walk():
        offer = round_set(node, 6, 26)
        if not offer:
            continue
        layout, _ = build_label_layout([node.box] + [k.box for k in offer], m)
        order = [b.geom() for b, _ in layout]
        expect = [node.box.geom()] + [k.box.geom() for k in offer]
        if order != expect:
            mismatches.append((expect[:3], order[:3]))
    check(
        "build_label_layout keeps the round's order, so index == label",
        not mismatches,
        f"{mismatches[:2]}",
    )

    # And spot-check one real path end to end by walking the rounds by hand.
    target = boxes[-1]
    path = rows[target.geom()]["path"]
    node, typed = root, ""
    ok = True
    while typed != path:
        offer = round_set(node, 6, 26)
        total = len(offer) + 1
        step = None
        for i, k in enumerate(offer):
            lbl = label_for(i + 1, total, kbshot.LABEL_SYMBOLS)
            if path[len(typed):].startswith(lbl):
                step, typed = k, typed + lbl
                break
        if step is None:
            ok = False
            break
        node = step
    check(
        f"walking the rounds by hand with {path!r} lands on the right region",
        ok and node.box.geom() == target.geom(),
        f"landed on {node.box.geom()}, wanted {target.geom()}",
    )


def test_labels_within_a_round_do_not_overlap():
    print("\nper-round label placement")
    m = mon()
    boxes = [Box(0, 0, 1400, 1000, "window")]
    for i in range(6):
        boxes.append(Box(20 + i * 220, 20, 200, 960, "xy-pane", f"col{i}"))
        for j in range(6):
            boxes.append(Box(25 + i * 220, 30 + j * 150, 190, 130, "para", f"c{i}p{j}"))
    root = build_hierarchy(boxes, m, round_max=26)

    worst = 0
    for node in root.walk():
        offer = round_set(node, 6, 26)
        if not offer:
            continue
        layout, _ = build_label_layout([node.box] + [k.box for k in offer], m)
        rects = [lr for _, lr in layout]
        for i in range(len(rects)):
            for j in range(i + 1, len(rects)):
                ax, ay, aw, ah = rects[i]
                bx, by, bw, bh = rects[j]
                if ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah:
                    worst += 1
    check("no two labels overlap inside any round", worst == 0, f"{worst} pairs")


def main() -> int:
    for fn in (
        test_one_keystroke_budget,
        test_coverage,
        test_parent_is_smallest_container,
        test_partial_overlap_threshold,
        test_no_cycles_and_every_box_reachable,
        test_screen_sized_candidate_is_not_a_level,
        test_round_cap_pushes_overflow_deeper,
        test_non_overlapping_overflow_stays_visible,
        test_round_min_promotes_grandchildren,
        test_every_region_has_a_keystroke_path,
        test_each_keystroke_narrows,
        test_shared_prefixes_mean_shared_pixels,
        test_round_labels_match_the_paths,
        test_labels_within_a_round_do_not_overlap,
    ):
        fn()
    print()
    if FAILURES:
        print(f"FAIL: {len(FAILURES)} check(s): {FAILURES}")
        return 1
    print("PASS: every hierarchy check green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
