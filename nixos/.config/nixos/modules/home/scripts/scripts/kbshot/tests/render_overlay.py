#!/usr/bin/env python3
"""Render the overlay onto an image, reproducing wl-kbptr's own draw order.

Used for documentation and for reviewing label placement without having to put a
keyboard-grabbing layer surface on a real screen. It is a faithful reproduction, not a
guess: the fill / 1px border / centred-text sequence and the colours are taken from
mode_floating.c and from kbshot's own palette, and the anchor rectangles come from
`kbshot --dump-candidates`, so what is drawn here is what the compositor would draw.

A hierarchical run draws one ROUND at a time, so a round is what gets rendered:
`--round 0` is what you see when the hotkey fires, `--round <geom>` is what you see
after picking that region. `--flat` renders the old everything-at-once overlay,
which is the picture to put next to it.

  render_overlay.py SCENE.png OUT.png [theme] [--round N|GEOM] [--flat]
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from kbshot import THEMES, LABEL_PT  # noqa: E402


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


FONT = _find_font("DejaVu Sans", "sans-serif")


def rgba(c: str) -> tuple[int, int, int, int]:
    h = c.lstrip("#")
    if len(h) == 6:
        h += "ff"
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4, 6))  # type: ignore[return-value]


def geom(s: str) -> tuple[int, int, int, int]:
    w, h, x, y = (int(v) for v in s.replace("x", "+").split("+"))
    return x, y, w, h


def main() -> int:
    argv = sys.argv[1:]
    flat = "--flat" in argv
    which: str = "0"
    if "--round" in argv:
        i = argv.index("--round")
        which = argv[i + 1]
        del argv[i : i + 2]
    argv = [a for a in argv if a != "--flat"]
    scene, out = Path(argv[0]), Path(argv[1])
    theme = argv[2] if len(argv) > 2 else "default"
    pal = THEMES[theme]
    kbshot = Path(__file__).resolve().parent.parent / "kbshot.py"

    with tempfile.TemporaryDirectory() as td:
        anchors_p = Path(td) / "a.json"
        subprocess.run(
            [sys.executable, str(kbshot), "--from-image", str(scene),
             "--assume-scale", "1.0", "--min-size", "45x27",
             "--dump-candidates", str(anchors_p), "--debug-json"]
            + (["--flat"] if flat else []),
            check=True, capture_output=True, text=True,
        )
        dump = json.loads(anchors_p.read_text())

    if isinstance(dump, dict):
        rounds = dump["rounds"]
        pick = (
            rounds[int(which)]
            if which.isdigit()
            else next(r for r in rounds if r["of"] == which)
        )
        items, note = pick["items"], f"round of {pick['of']}"
    else:
        items, note = dump, "flat: every candidate at once"

    base = Image.open(scene).convert("RGBA")
    # unselectable_bg_color dims everything; then each AREA gets a translucent fill
    # and a 1px border, and only after that does each LABEL rect get its opaque
    # backing and text. Two passes, in that order, exactly as the patched
    # mode_floating.c does it -- a label drawn before a neighbouring area's fill
    # would be painted over.
    layer = Image.new("RGBA", base.size, rgba(pal["dim"]))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(FONT, LABEL_PT)
    fill, border = rgba(pal["fill"]), rgba(pal["border"])
    label_c, typed_c = rgba(pal["label"]), rgba(pal["typed"])
    area_fill = rgba(pal["border"][:7] + "1f")

    for a in items:
        if a.get("region"):
            x, y, w, h = geom(a["region"])
            d.rectangle([x, y, x + w, y + h], fill=area_fill)
            d.rectangle([x + 0.5, y + 0.5, x + w - 1, y + h - 1], outline=border, width=1)
    for a in items:
        x, y, w, h = geom(a["anchor"])
        d.rectangle([x, y, x + w, y + h], fill=fill)
        text = a["label"]
        tb = d.textbbox((0, 0), text, font=font)
        tx = x + (w - (tb[2] - tb[0])) / 2
        ty = y + (h + (tb[3] - tb[1])) / 2 - (tb[3] - tb[1])
        # First character shown as already-typed, to document the two-colour state.
        d.text((tx, ty), text[0], font=font, fill=typed_c)
        adv = d.textlength(text[0], font=font)
        if len(text) > 1:
            d.text((tx + adv, ty), text[1:], font=font, fill=label_c)

    Image.alpha_composite(base, layer).convert("RGB").save(out)
    print(f"{out} — {len(items)} labels, theme={theme}, {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
