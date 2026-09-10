#!/usr/bin/env python3
"""Measure the overlay palettes instead of asserting they look fine.

Two things are checked, and both are failure modes that a screenshot of a
good-looking overlay would hide:

 1. **Composited contrast.** wl-kbptr has no label backing of its own -- it fills the
    area with `selectable_bg_color`, then draws the label straight on top. So the
    label's real contrast is against the fill *composited over whatever was already
    on screen*. A palette must therefore clear the WCAG AAA bar (7:1) over every
    plausible background, not over an idealised one. This is what caught the old
    13%-alpha fill: white label over a white page composited to white on white.

 2. **Colour-vision deficiency.** The `colorblind` palette must not encode any
    distinction in hue alone. It is verified by transforming each colour through
    Machado et al.'s severity-1.0 deuteranopia / protanopia / tritanopia matrices and
    re-measuring; if a distinction survives only because of hue, one of those three
    collapses it and the ratio drops.

Run: python3 test_contrast.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from kbshot import THEMES  # noqa: E402

# Backgrounds a chip realistically lands on: a white article, a light IDE, mid grey,
# a dark IDE, near-black, and a saturated dashboard accent.
BACKGROUNDS = {
    "white-page": (0xFF, 0xFF, 0xFF),
    "light-ide": (0xFA, 0xFA, 0xFC),
    "mid-grey": (0x80, 0x80, 0x80),
    "dark-ide": (0x1E, 0x1E, 0x2E),
    "near-black": (0x0B, 0x0B, 0x0B),
    "accent-blue": (0x1A, 0x73, 0xE8),
    "accent-red": (0xD9, 0x3A, 0x3A),
}

AAA = 7.0
AA = 4.5

# Machado, Oliveira & Fernandes (2009) CVD simulation matrices, severity 1.0.
CVD = {
    "deuteranopia": (
        (0.367322, 0.860646, -0.227968),
        (0.280085, 0.672501, 0.047413),
        (-0.011820, 0.042940, 0.968881),
    ),
    "protanopia": (
        (0.152286, 1.052583, -0.204868),
        (0.114503, 0.786281, 0.099216),
        (-0.003882, -0.048116, 1.051998),
    ),
    "tritanopia": (
        (1.255528, -0.076749, -0.178779),
        (-0.078411, 0.930809, 0.147602),
        (0.004733, 0.691367, 0.303900),
    ),
}


def parse(c: str) -> tuple[int, int, int, int]:
    """wl-kbptr's #rrggbbaa (config.c parse_color: 8 digits, alpha last)."""
    h = c.lstrip("#")
    if len(h) == 6:
        h += "ff"
    if len(h) != 8:
        raise ValueError(f"expected #rrggbbaa, got {c!r}")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4, 6))  # type: ignore[return-value]


def over(fg: tuple[int, int, int, int], bg: tuple[int, int, int]) -> tuple[float, float, float]:
    """Source-over composite of an RGBA colour onto an opaque background."""
    a = fg[3] / 255.0
    return tuple(fg[i] * a + bg[i] * (1 - a) for i in range(3))  # type: ignore[return-value]


def luminance(rgb) -> float:
    """WCAG 2.1 relative luminance."""
    out = []
    for v in rgb:
        s = v / 255.0
        out.append(s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4)
    return 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2]


def ratio(a, b) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def simulate(rgb, kind: str):
    m = CVD[kind]
    return tuple(
        min(255.0, max(0.0, sum(m[r][c] * rgb[c] for c in range(3)))) for r in range(3)
    )


def main() -> int:
    failures: list[str] = []
    print("=" * 76)
    print("LABEL-ON-CHIP CONTRAST, composited over real backgrounds (WCAG 2.1)")
    print("=" * 76)

    for name, pal in THEMES.items():
        fill = parse(pal["fill"])
        label = parse(pal["label"])
        typed = parse(pal["typed"])
        print(f"\n[{name}]  fill={pal['fill']} label={pal['label']} typed={pal['typed']}")
        worst_label = worst_typed = 99.0
        for bgname, bg in BACKGROUNDS.items():
            chip = over(fill, bg)
            lab = over(label, chip)
            typ = over(typed, chip)
            rl, rt = ratio(lab, chip), ratio(typ, chip)
            worst_label = min(worst_label, rl)
            worst_typed = min(worst_typed, rt)
            flag = "" if rl >= AAA else ("  <-- below AAA" if rl >= AA else "  <-- FAIL")
            print(f"   over {bgname:<12} label {rl:5.2f}:1   typed {rt:5.2f}:1{flag}")
        print(f"   worst case: label {worst_label:.2f}:1   typed {worst_typed:.2f}:1")
        if worst_label < AAA:
            failures.append(f"{name}: label contrast {worst_label:.2f}:1 < AAA {AAA}")
        if worst_typed < AA:
            failures.append(f"{name}: typed-prefix contrast {worst_typed:.2f}:1 < AA {AA}")

        # The typed prefix must be tellable apart from the untyped remainder, which is
        # the cue for "how much of this label have I entered". >= 1.6:1 between them.
        chip = over(fill, BACKGROUNDS["mid-grey"])
        sep = ratio(over(label, chip), over(typed, chip))
        print(f"   typed vs untyped separation: {sep:.2f}:1")
        if sep < 1.6:
            failures.append(f"{name}: typed/untyped separation only {sep:.2f}:1")

    print("\n" + "=" * 76)
    print("COLOUR-VISION DEFICIENCY (colorblind palette must not rely on hue)")
    print("=" * 76)
    pal = THEMES["colorblind"]
    fill, label, typed, border = (parse(pal[k]) for k in ("fill", "label", "typed", "border"))
    for bgname in ("white-page", "dark-ide"):
        bg = BACKGROUNDS[bgname]
        chip = over(fill, bg)
        print(f"\n  over {bgname}:")
        for kind in ["normal"] + list(CVD):
            f = chip if kind == "normal" else simulate(chip, kind)
            l_ = over(label, chip) if kind == "normal" else simulate(over(label, chip), kind)
            t_ = over(typed, chip) if kind == "normal" else simulate(over(typed, chip), kind)
            b_ = over(border, chip) if kind == "normal" else simulate(over(border, chip), kind)
            rl, rt, rb = ratio(l_, f), ratio(t_, f), ratio(b_, f)
            sep = ratio(l_, t_)
            flag = "" if rl >= AAA and sep >= 1.6 else "  <-- FAIL"
            print(f"    {kind:<14} label {rl:5.2f}:1  typed {rt:5.2f}:1  "
                  f"border {rb:5.2f}:1  typed/untyped {sep:4.2f}:1{flag}")
            if rl < AAA:
                failures.append(f"colorblind/{kind} over {bgname}: label {rl:.2f}:1 < AAA")
            if sep < 1.6:
                failures.append(
                    f"colorblind/{kind} over {bgname}: typed/untyped {sep:.2f}:1 < 1.6"
                )

    print("\n" + "=" * 76)
    if failures:
        print(f"FAIL ({len(failures)})")
        for f in failures:
            print("  -", f)
        return 1
    print("PASS: every palette clears AAA for label text on its chip over every tested")
    print("background, and the colorblind palette holds up under all three CVD types.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
