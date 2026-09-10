#!/usr/bin/env python3
"""kbshot eval harness.

Scores the candidate-generation and labelling pipeline against ground truth, so
"detection got better" is a number rather than an opinion.

Two independent families of check, because they fail for different reasons:

  SEMANTIC  -- given hand- or generator-annotated target regions, does the tool
               actually OFFER that region, and how many keystrokes does it cost?
               This is the eval that says whether a Slack message is one box or
               six word boxes.

  STRUCTURAL -- properties that must hold on ANY screen, no annotation needed:
               labels must not overlap, every offered box must clear the minimum
               size, labels must be unique, two runs on the same image must
               produce the same labels (or no muscle memory can ever form), and
               a box that contains another must still be reachable.

Run:  harness.py --scenes DIR [--scenes DIR ...] [--gt FILE] [-o OUT.json]
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Invoke the script under test directly with this interpreter, so the harness needs
# no wrapper and no installed copy.
KBSHOT = HERE.parent / "kbshot.py"

# Matt's panel is 2880x1800px over 2160x1350 logical (scale exactly 4/3). Corpus
# and scene images are native pixels, and the harness runs detection at
# --assume-scale 1.0 so that every coordinate in this file -- ground truth,
# candidates, IoU -- is in image pixels with no conversion anywhere.
#
# The consequence is that the tool's logical-px thresholds must be converted to
# pixels by hand, or the eval would silently test a laxer minimum size than real
# usage enforces. 34x20 logical is 45x27 physical at 4/3.
REAL_SCALE = 4.0 / 3.0
MIN_SIZE_LOGICAL = (34, 20)
MIN_SIZE_PX = (
    round(MIN_SIZE_LOGICAL[0] * REAL_SCALE),
    round(MIN_SIZE_LOGICAL[1] * REAL_SCALE),
)

IOU_STRICT = 0.70
IOU_LOOSE = 0.50


def iou(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ix1, iy1 = max(ax, bx), max(ay, by)
    ix2, iy2 = min(ax + aw, bx + bw), min(ay + ah, by + bh)
    iw, ih = max(0, ix2 - ix1), max(0, iy2 - iy1)
    inter = iw * ih
    if inter == 0:
        return 0.0
    return inter / (aw * ah + bw * bh - inter)


def parse_geom(g: str) -> tuple[int, int, int, int]:
    m = re.fullmatch(r"(\d+)x(\d+)\+(-?\d+)\+(-?\d+)", g)
    if not m:
        raise ValueError(f"bad geom {g!r}")
    w, h, x, y = (int(v) for v in m.groups())
    return x, y, w, h


def overlaps(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> bool:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah


def run_detect(image: Path, extra: list[str] | None = None) -> dict:
    """Run the real CLI on an image and return candidates, anchors, and timing."""
    tmp = Path(tempfile.mkdtemp(prefix="kbeval-"))
    try:
        cands_p = tmp / "cands.json"
        anchors_p = tmp / "anchors.json"
        cmd = [
            sys.executable,
            str(KBSHOT),
            "--from-image",
            str(image),
            "--assume-scale",
            "1.0",
            "--min-size",
            f"{MIN_SIZE_PX[0]}x{MIN_SIZE_PX[1]}",
            "--debug-json",
            "--dump-candidates",
            str(anchors_p),
            "-v",
        ] + (extra or [])
        t0 = time.monotonic()
        proc = subprocess.run(cmd, capture_output=True, text=True)
        wall = time.monotonic() - t0
        if proc.returncode != 0:
            return {"ok": False, "error": proc.stderr.strip()[-800:], "wall": wall}
        cands_p.write_text(proc.stdout)
        cands = json.loads(proc.stdout)
        anchors = json.loads(anchors_p.read_text()) if anchors_p.exists() else []
        # `-v` reports the stage timings; the detect time excludes process startup,
        # which is what a latency budget actually cares about.
        detect = None
        m = re.search(r"([\d.]+) offered, ready in ([\d.]+)s", proc.stderr)
        if m:
            detect = float(m.group(2))
        else:
            m2 = re.search(r"ready in ([\d.]+)s", proc.stderr)
            detect = float(m2.group(1)) if m2 else None
        return {
            "ok": True,
            "cands": cands,
            "anchors": anchors,
            "wall": wall,
            "detect": detect,
            "stderr": proc.stderr,
        }
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def keystrokes_for(anchors: list[dict] | dict, target_geom: str) -> int | None:
    """How many characters the user must type to land on `target_geom`.

    Hierarchical runs report it directly: the tool walks the same round-building
    code to produce the path, so the number is the real one rather than a model of
    it. A region with something inside it costs one more key, the Return that says
    "this one, do not drill further".

    In the flat layout a candidate lives inside exactly one anchor group. Reaching
    it costs the anchor's label length, plus one more round if the group holds more
    than one member (the second round re-labels just that group).
    """
    if isinstance(anchors, dict):
        if target_geom == anchors.get("root"):
            return 1  # Return, on the first round
        for r in anchors.get("regions", []):
            if r["geom"] == target_geom:
                return r["keystrokes"]
        return None
    for a in anchors:
        geoms = [m["geom"] for m in a["members"]]
        if target_geom in geoms:
            cost = len(a["label"])
            if len(geoms) > 1:
                # Round two labels len(group) items, so ceil(log_18(n)) more chars.
                n = len(geoms)
                extra, cap = 1, 18
                while cap < n:
                    cap *= 18
                    extra += 1
                cost += extra
            return cost
    return None


def score_semantic(image: Path, targets: list[dict], det: dict) -> dict:
    cand_boxes = [(c["geom"], parse_geom(c["geom"]), c["tier"]) for c in det["cands"]]
    rows = []
    for t in targets:
        gt = tuple(t["bbox"])
        best_iou, best = 0.0, None
        for geom, box, tier in cand_boxes:
            v = iou(gt, box)
            if v > best_iou:
                best_iou, best = v, (geom, tier)
        ks = keystrokes_for(det["anchors"], best[0]) if best and best_iou >= IOU_LOOSE else None
        rows.append(
            {
                "id": t["id"],
                "kind": t["kind"],
                "priority": t.get("priority", "primary"),
                "bbox": list(gt),
                "best_iou": round(best_iou, 3),
                "hit_strict": best_iou >= IOU_STRICT,
                "hit_loose": best_iou >= IOU_LOOSE,
                "matched_tier": best[1] if best else None,
                "keystrokes": ks,
            }
        )
    return {"targets": rows}


def _label_groups(anchors: list[dict] | dict) -> list[list[dict]]:
    """The sets of labels drawn on screen at the same time.

    Flat: one set, everything at once. Hierarchical: one set per round, because a
    round is what is actually on screen, and two rounds' labels can never collide.
    """
    if isinstance(anchors, dict):
        return [r["items"] for r in anchors.get("rounds", [])]
    return [anchors]


def prefix_overlap_profile(regions: list[dict]) -> dict[str, float]:
    """Mean pairwise overlap, bucketed by how many leading keys two regions share.

    The feature's claim in one number. If it works, the profile rises steeply: two
    regions you reach with the same first key are largely the same pixels, and two
    that differ in the first key are not. A labelling that carries no structure
    comes out flat, so this is a measurement that can come back negative.
    """
    acc: dict[int, list[float]] = defaultdict(list)
    for i in range(len(regions)):
        ax, ay, aw, ah = parse_geom(regions[i]["geom"])
        pa = regions[i]["path"]
        for j in range(i + 1, len(regions)):
            bx, by, bw, bh = parse_geom(regions[j]["geom"])
            pb = regions[j]["path"]
            n = 0
            while n < min(len(pa), len(pb)) and pa[n] == pb[n]:
                n += 1
            ox = max(0, min(ax + aw, bx + bw) - max(ax, bx))
            oy = max(0, min(ay + ah, by + bh) - max(ay, by))
            inter = ox * oy
            acc[n].append(inter / max(1, min(aw * ah, bw * bh)))
    return {str(k): sum(v) / len(v) for k, v in sorted(acc.items()) if len(v) >= 5}


def score_structural(image: Path, det: dict) -> dict:
    cands = det["cands"]
    anchors = det["anchors"]
    tree = isinstance(anchors, dict)
    problems: list[str] = []

    # 1. No two labels may overlap on screen. This is THE complaint that started
    #    the anchor redesign, so it is checked as a hard invariant -- per round,
    #    since a round is what is on screen at one time.
    overlap_pairs = 0
    for group in _label_groups(anchors):
        arects = [parse_geom(a["anchor"]) for a in group]
        for i in range(len(arects)):
            for j in range(i + 1, len(arects)):
                if overlaps(arects[i], arects[j]):
                    overlap_pairs += 1
    if overlap_pairs:
        problems.append(f"{overlap_pairs} overlapping label pairs")

    # 2. Every offered region clears the minimum size.
    too_small = [c["geom"] for c in cands
                 if parse_geom(c["geom"])[2] < MIN_SIZE_PX[0]
                 or parse_geom(c["geom"])[3] < MIN_SIZE_PX[1]]
    if too_small:
        problems.append(f"{len(too_small)} candidates below min size {MIN_SIZE_PX}")

    # 3. Two regions must never answer to the same keys. Flat: labels are unique.
    #    Hierarchical: labels repeat across rounds by design, so what has to be
    #    unique is the whole path -- the keys typed from the first round.
    if tree:
        keys = [r["path"] for r in anchors.get("regions", [])]
    else:
        keys = [a["label"] for a in anchors]
    dupes = [l for l, n in Counter(keys).items() if n > 1]
    if dupes:
        problems.append(f"duplicate {'paths' if tree else 'labels'}: {dupes[:5]}")

    # 4. Every candidate must be reachable.
    if tree:
        # The whole-output candidate is the tree's root rather than an item in it,
        # so it has no path -- Return on the first round is what captures it.
        reachable = {r["geom"] for r in anchors.get("regions", [])} | {anchors["root"]}
        # A round whose labels could not all be placed makes the picker ask a
        # follow-up question that the reported paths do not include, so the
        # keystroke numbers below would understate the real cost.
        crowded = [
            r["of"] for r in anchors.get("rounds", []) if len(r["items"]) != r["offered"]
        ]
        if crowded:
            problems.append(f"{len(crowded)} rounds could not label every region")
    else:
        reachable = {m["geom"] for a in anchors for m in a["members"]}
    unreachable = [c["geom"] for c in cands if c["geom"] not in reachable]
    if unreachable:
        problems.append(f"{len(unreachable)} candidates unreachable by any label")

    # 5. Nesting: for every containment pair, both must be selectable. The whole
    #    point of the grouping round is that an element inside an element stays
    #    reachable, so a containment pair that collapses to one label is a bug.
    boxes = [parse_geom(c["geom"]) for c in cands]
    nested_pairs = 0
    for i, bi in enumerate(boxes):
        for j, bj in enumerate(boxes):
            if i == j:
                continue
            xi, yi, wi, hi = bi
            xj, yj, wj, hj = bj
            if xi <= xj and yi <= yj and xi + wi >= xj + wj and yi + hi >= yj + hj:
                if wi * hi > wj * hj:
                    nested_pairs += 1
    both_reachable = all(
        keystrokes_for(anchors, c["geom"]) is not None for c in cands
    )
    if not both_reachable:
        problems.append("some candidate has no keystroke path")

    # 6. Junk: extreme slivers are almost never a wanted screenshot and they eat
    #    labels that a real region needed.
    slivers = 0
    for x, y, w, h in boxes:
        ar = w / max(1, h)
        if ar > 60 or ar < 1 / 60:
            slivers += 1

    if tree:
        regions = anchors.get("regions", [])
        rounds = anchors.get("rounds", [])
        ks = [r["keystrokes"] for r in regions]
        out = {
            "labels": len(regions),
            "rounds": len(rounds),
            "first_round": rounds[0]["offered"] if rounds else 0,
            "biggest_round": max((r["offered"] for r in rounds), default=0),
            "max_depth": max((r["depth"] for r in regions), default=0),
            "prefix_overlap": prefix_overlap_profile(regions),
            "grouped_labels": 0,
            "biggest_group": 0,
        }
    else:
        ks = [len(a["label"]) for a in anchors]
        out = {
            "labels": len(anchors),
            # Same measurement on the flat labelling, so the hierarchy's number has
            # something to be compared against rather than just being large.
            "prefix_overlap": prefix_overlap_profile(
                [
                    {"geom": a.get("region", a["anchor"]), "path": a["label"]}
                    for a in anchors
                ]
            ),
            "grouped_labels": sum(1 for a in anchors if len(a["members"]) > 1),
            "biggest_group": max((len(a["members"]) for a in anchors), default=0),
        }
    return {
        "candidates": len(cands),
        "overlap_pairs": overlap_pairs,
        "below_min_size": len(too_small),
        "duplicate_labels": len(dupes),
        "unreachable": len(unreachable),
        "nested_pairs": nested_pairs,
        "slivers": slivers,
        "label_len_max": max(ks, default=0),
        "tiers": dict(Counter(c["tier"] for c in cands)),
        "problems": problems,
        **out,
    }


def check_determinism(image: Path) -> dict:
    """Same image twice must yield identical labels, or muscle memory is impossible."""
    a = run_detect(image)
    b = run_detect(image)
    if not (a["ok"] and b["ok"]):
        return {"ok": False, "reason": "a detection run failed"}
    def fingerprint(det: dict) -> list:
        anchors = det["anchors"]
        if isinstance(anchors, dict):
            # The path is the thing muscle memory holds, so that is what must not
            # move between runs -- not just the label drawn in one round.
            return [(r["path"], r["geom"]) for r in anchors.get("regions", [])]
        return [(x["label"], x["anchor"]) for x in anchors]

    la, lb = fingerprint(a), fingerprint(b)
    return {"ok": True, "identical": la == lb, "n": len(la)}


def main() -> int:
    ap = argparse.ArgumentParser(description="kbshot detection eval harness")
    ap.add_argument("--scenes", action="append", default=[], metavar="DIR",
                    help="directory of images; its ground_truth.json is used if present")
    ap.add_argument("--gt", action="append", default=[], metavar="JSON",
                    help="extra ground-truth file (schema: scene,id,kind,bbox,priority)")
    ap.add_argument("--only", help="substring filter on image filename")
    ap.add_argument("-o", "--out", default=str(HERE / "out" / "scorecard.json"))
    ap.add_argument("--determinism", action="store_true", help="also run the repeat-run check")
    ap.add_argument("--extra", default="", help="extra args to pass through to kbshot")
    args = ap.parse_args()

    # Gather ground truth keyed by image filename.
    gt_by_scene: dict[str, list[dict]] = defaultdict(list)
    gt_files = [Path(g) for g in args.gt]
    images: list[Path] = []
    for d in args.scenes:
        dp = Path(d)
        if not dp.is_dir():
            print(f"harness: no such dir {d}", file=sys.stderr)
            continue
        images += sorted(p for p in dp.glob("*.png") if not p.name.startswith("verify-"))
        cand_gt = dp / "ground_truth.json"
        if cand_gt.is_file():
            gt_files.append(cand_gt)
    for g in gt_files:
        if not g.is_file():
            continue
        for row in json.loads(g.read_text()):
            gt_by_scene[Path(row["scene"]).name].append(row)

    if args.only:
        images = [p for p in images if args.only in p.name]
    if not images:
        print("harness: no images to score", file=sys.stderr)
        return 2

    extra = args.extra.split() if args.extra else []
    results = []
    for img in images:
        det = run_detect(img, extra)
        if not det["ok"]:
            print(f"  FAIL {img.name}: {det['error'][:200]}")
            results.append({"image": img.name, "ok": False, "error": det["error"]})
            continue
        targets = gt_by_scene.get(img.name, [])
        entry = {
            "image": img.name,
            "ok": True,
            "wall_s": round(det["wall"], 2),
            "detect_s": det["detect"],
            "structural": score_structural(img, det),
        }
        if targets:
            entry["semantic"] = score_semantic(img, targets, det)
        results.append(entry)
        st = entry["structural"]
        shape = (f"r1={st['first_round']:<3} deep={st['max_depth']:<2}"
                 if "first_round" in st else f"grp={st['grouped_labels']:<3}")
        line = (f"  {img.name:<30} {st['candidates']:>4} cand  {st['labels']:>4} lbl  "
                f"ovl={st['overlap_pairs']:<3} {shape} "
                f"{det['detect'] if det['detect'] is not None else '?'}s")
        if targets:
            sem = entry["semantic"]["targets"]
            prim = [t for t in sem if t["priority"] == "primary"]
            hs = sum(1 for t in prim if t["hit_strict"])
            hl = sum(1 for t in prim if t["hit_loose"])
            line += f"  primary {hs}/{len(prim)}@.7 {hl}/{len(prim)}@.5"
        print(line)

    # ---------------- aggregate scorecard ----------------
    ok = [r for r in results if r.get("ok")]
    allsem = [t for r in ok for t in r.get("semantic", {}).get("targets", [])]
    prim = [t for t in allsem if t["priority"] == "primary"]
    sec = [t for t in allsem if t["priority"] != "primary"]

    def pct(n, d):
        return f"{100.0 * n / d:.1f}%" if d else "n/a"

    print()
    print("=" * 78)
    print("SCORECARD")
    print("=" * 78)
    print(f"images scored ............. {len(ok)}/{len(results)}")
    if prim:
        hs = sum(1 for t in prim if t["hit_strict"])
        hl = sum(1 for t in prim if t["hit_loose"])
        print(f"PRIMARY recall @IoU {IOU_STRICT} .. {hs}/{len(prim)}  ({pct(hs, len(prim))})")
        print(f"PRIMARY recall @IoU {IOU_LOOSE} .. {hl}/{len(prim)}  ({pct(hl, len(prim))})")
        med = statistics.median(t["best_iou"] for t in prim)
        print(f"PRIMARY median best IoU ... {med:.3f}")
        ksv = [t["keystrokes"] for t in prim if t["keystrokes"]]
        if ksv:
            print(f"keystrokes to a primary ... mean {statistics.mean(ksv):.2f}  max {max(ksv)}")
        by_kind: dict[str, list[dict]] = defaultdict(list)
        for t in prim:
            by_kind[t["kind"]].append(t)
        print("\n  recall by kind (primary targets):")
        for kind, ts in sorted(by_kind.items(), key=lambda kv: -len(kv[1])):
            h = sum(1 for t in ts if t["hit_strict"])
            hlk = sum(1 for t in ts if t["hit_loose"])
            flag = "  <-- WEAK" if len(ts) and h / len(ts) < 0.5 else ""
            print(f"    {kind:<22} {h:>3}/{len(ts):<3} @.7   {hlk:>3}/{len(ts):<3} @.5{flag}")
    if sec:
        hs = sum(1 for t in sec if t["hit_strict"])
        print(f"\nsecondary recall @IoU {IOU_STRICT} {hs}/{len(sec)}  ({pct(hs, len(sec))})")

    tot_ovl = sum(r["structural"]["overlap_pairs"] for r in ok)
    tot_small = sum(r["structural"]["below_min_size"] for r in ok)
    tot_unreach = sum(r["structural"]["unreachable"] for r in ok)
    tot_dupe = sum(r["structural"]["duplicate_labels"] for r in ok)
    print("\nSTRUCTURAL invariants (must all be 0):")
    print(f"  overlapping label pairs . {tot_ovl}")
    print(f"  below min size .......... {tot_small}")
    print(f"  unreachable candidates .. {tot_unreach}")
    print(f"  duplicate labels ........ {tot_dupe}")
    slivers = sum(r["structural"]["slivers"] for r in ok)
    print(f"  sliver candidates ....... {slivers}  (informational)")
    if ok and "first_round" in ok[0]["structural"]:
        r1 = [r["structural"]["first_round"] for r in ok]
        big = [r["structural"]["biggest_round"] for r in ok]
        deep = [r["structural"]["max_depth"] for r in ok]
        print("\nHIERARCHY shape:")
        print(f"  regions offered first ... median {statistics.median(r1):.0f}  "
              f"max {max(r1)}   (was every candidate at once)")
        print(f"  biggest single round .... max {max(big)}")
        print(f"  deepest region .......... max {max(deep)} rounds")
    prof: dict[str, list[float]] = defaultdict(list)
    for r in ok:
        for k, v in r["structural"].get("prefix_overlap", {}).items():
            prof[k].append(v)
    if prof:
        means = {k: statistics.mean(v) for k, v in sorted(prof.items())}
        print("\nPREFIX <-> OVERLAP (keys two regions share -> pixels they share):")
        print("  " + "   ".join(f"{k}:{v:.3f}" for k, v in means.items()))
        print("  must rise steeply -- that IS the claim. Flat labelling is the control.")
    dts = [r["detect_s"] for r in ok if r.get("detect_s")]
    if dts:
        print(f"\nlatency to overlay ........ median {statistics.median(dts):.2f}s  "
              f"max {max(dts):.2f}s")

    det_res = None
    if args.determinism and ok:
        img = next(p for p in images if p.name == ok[0]["image"])
        det_res = check_determinism(img)
        verdict = "IDENTICAL" if det_res.get("identical") else "DIFFERS (bug)"
        print(f"\ndeterminism (same image twice on {img.name}): {verdict}")

    # A run that scored nothing used to print STRUCTURAL PASS, which is the worst
    # possible failure mode for an eval: every invariant is trivially 0 when there
    # is no data, so a crashing detector looked like a clean bill of health.
    invariants_pass = (
        len(ok) == len(results)
        and bool(ok)
        and tot_ovl == 0
        and tot_small == 0
        and tot_unreach == 0
        and tot_dupe == 0
    )
    if not ok:
        print("\nNO IMAGE SCORED -- the invariants below are vacuous")
    elif len(ok) != len(results):
        print(f"\n{len(results) - len(ok)} image(s) failed to run")
    print("\nverdict: " + ("STRUCTURAL PASS" if invariants_pass else "STRUCTURAL FAIL"))

    outp = Path(args.out)
    outp.parent.mkdir(parents=True, exist_ok=True)
    outp.write_text(json.dumps(
        {"results": results, "determinism": det_res,
         "min_size_px": list(MIN_SIZE_PX), "iou": [IOU_STRICT, IOU_LOOSE]}, indent=1))
    print(f"wrote {outp}")
    return 0 if invariants_pass else 1


if __name__ == "__main__":
    sys.exit(main())
