#!/usr/bin/env python3
"""Probe the XY-cut projection profiles on a real frame to pick a blank tolerance.

Guessing a tolerance is how you get a detector that works on one screenshot. This
prints the actual distribution of per-row and per-column ink counts so the
threshold is chosen from the data.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

png = Path(sys.argv[1])
detect_width = 1440

img = Image.open(png).convert("L")
f = min(1.0, detect_width / img.width)
img = img.resize((round(img.width * f), round(img.height * f)), Image.BILINEAR)
grey = np.asarray(img, dtype=np.float32)
gx = ndimage.sobel(grey, axis=1)
gy = ndimage.sobel(grey, axis=0)
edges = np.hypot(gx, gy) > 45.0
ink = ndimage.maximum_filter(edges, size=(2, 3), mode="constant", cval=False)

h, w = ink.shape
rc = ink.sum(axis=1)
cc = ink.sum(axis=0)
print(f"{png.name}: ink {ink.shape}, density {ink.mean():.3f}")
for name, prof, span in (("row", rc, w), ("col", cc, h)):
    q = np.percentile(prof, [0, 1, 5, 10, 25, 50, 90, 100])
    print(f"  {name} ink counts (span {span}): min={q[0]:.0f} p1={q[1]:.0f} "
          f"p5={q[2]:.0f} p10={q[3]:.0f} p25={q[4]:.0f} med={q[5]:.0f} max={q[7]:.0f}")
    for frac in (0.0, 0.002, 0.005, 0.01, 0.02, 0.04):
        tol = max(0, int(frac * span))
        blank = prof <= tol
        # longest run of blank
        best = cur = 0
        runs = []
        for b in blank:
            if b:
                cur += 1
            else:
                if cur:
                    runs.append(cur)
                cur = 0
        if cur:
            runs.append(cur)
        runs.sort(reverse=True)
        print(f"    tol={frac:<6} ({tol:>3}px): {blank.sum():>4} blank slots, "
              f"{len(runs)} runs, top runs {runs[:6]}")
