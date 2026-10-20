#!/usr/bin/env bash
# Memory in use, in GiB, as Activity Monitor's "Memory Used" counts it:
# app memory (anonymous - purgeable) + wired + compressed. "Pages active"
# would count file cache and miss inactive app pages; btop's "Used" is
# active + wired and leaves the compressor out entirely.
/usr/bin/vm_stat | /usr/bin/awk '
  /page size of/            { ps = $8 }
  /Anonymous pages/         { an = $3 }
  /Pages purgeable/         { p = $3 }
  /Pages wired down/        { w = $4 }
  /Pages occupied by compressor/ { c = $5 }
  END {
    gsub(/\./, "", an); gsub(/\./, "", p); gsub(/\./, "", w); gsub(/\./, "", c)
    used = (an - p + w + c) * ps / 1073741824
    printf "%.1fG\n", used
  }' | /usr/bin/xargs -I{} /opt/homebrew/bin/sketchybar --set "$NAME" label="{}"
