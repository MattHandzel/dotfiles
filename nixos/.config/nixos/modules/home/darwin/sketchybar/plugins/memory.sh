#!/usr/bin/env bash
# Memory in use, in GB, the way waybar showed it: active + wired + compressed.
/usr/bin/vm_stat | /usr/bin/awk '
  /page size of/            { ps = $8 }
  /Pages active/            { a = $3 }
  /Pages wired down/        { w = $4 }
  /Pages occupied by compressor/ { c = $5 }
  END {
    gsub(/\./, "", a); gsub(/\./, "", w); gsub(/\./, "", c)
    used = (a + w + c) * ps / 1073741824
    printf "%.1fG\n", used
  }' | /usr/bin/xargs -I{} /opt/homebrew/bin/sketchybar --set "$NAME" label="{}"
