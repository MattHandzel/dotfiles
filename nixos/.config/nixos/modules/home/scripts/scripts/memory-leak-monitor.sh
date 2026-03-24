#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   memory-leak-monitor [minutes] [interval_seconds]
# Example:
#   memory-leak-monitor 60 60

minutes="${1:-60}"
interval="${2:-60}"

if ! [[ "$minutes" =~ ^[0-9]+$ ]] || ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$minutes" -le 0 ] || [ "$interval" -le 0 ]; then
  echo "Usage: memory-leak-monitor [minutes] [interval_seconds]" >&2
  exit 1
fi

samples=$(( (minutes * 60) / interval ))
if [ "$samples" -le 0 ]; then
  echo "Computed sample count is 0. Increase minutes or lower interval." >&2
  exit 1
fi
timestamp="$(date +%Y%m%d-%H%M%S)"
out_dir="/tmp/memory-leak-report-${timestamp}"
mkdir -p "$out_dir"

series_tsv="$out_dir/series.tsv"
summary_md="$out_dir/summary.md"

echo -e "sample\tts\tpid\tppid\tuser\tcomm\trss_kb\tswap_kb\tetimes_s" > "$series_tsv"

collect_swap_kb() {
  local pid="$1"
  local status_file="/proc/${pid}/status"
  [ -r "$status_file" ] || { echo 0; return; }
  awk '/^VmSwap:/ {print $2; found=1} END {if (!found) print 0}' "$status_file" 2>/dev/null
}

echo "Collecting ${samples} samples (every ${interval}s) into ${out_dir}"

for ((i = 0; i < samples; i++)); do
  ts="$(date -Is)"

  {
    echo "=== sample ${i} ${ts} ==="
    free -m
    echo
    cat /proc/pressure/memory 2>/dev/null || true
    echo
  } >> "$out_dir/system.txt"

  while IFS=$'\t' read -r pid ppid user rss etimes comm; do
    swap_kb="$(collect_swap_kb "$pid")"
    echo -e "${i}\t${ts}\t${pid}\t${ppid}\t${user}\t${comm}\t${rss}\t${swap_kb}\t${etimes}" >> "$series_tsv"
  done < <(
    ps -eo pid=,ppid=,user=,rss=,etimes=,comm= --no-headers --sort=-rss \
      | head -n 160 \
      | awk '{
          pid=$1; ppid=$2; user=$3; rss=$4; etimes=$5;
          $1=$2=$3=$4=$5="";
          sub(/^ +/, "", $0);
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", pid, ppid, user, rss, etimes, $0;
        }'
  )

  if [ "$i" -lt $((samples - 1)) ]; then
    sleep "$interval"
  fi
done

awk -F '\t' '
NR == 1 { next }
{
  key = $3 "|" $5 "|" $6;   # pid|user|comm
  sample = $1 + 0;
  rss = $7 + 0;
  swp = $8 + 0;
  seen[key] = 1;
  rssv[key, sample] = rss;
  swpv[key, sample] = swp;
}
END {
  print "# Memory Leak Monitor Summary";
  print "";
  print "Generated at: " strftime("%Y-%m-%d %H:%M:%S");
  print "";
  print "## Sustained RSS growth (present in all samples, monotonic increase)";
  print "";
  print "| PID | User | Command | Start RSS (KB) | End RSS (KB) | Delta RSS (KB) | Start Swap (KB) | End Swap (KB) |";
  print "|---:|---|---|---:|---:|---:|---:|---:|";

  found = 0;
  for (k in seen) {
    ok = 1;
    for (s = 0; s < '"$samples"'; s++) {
      if (!((k SUBSEP s) in rssv)) {
        ok = 0;
        break;
      }
      if (s > 0 && rssv[k, s] <= rssv[k, s - 1]) {
        ok = 0;
      }
    }
    if (ok) {
      split(k, a, "|");
      start_r = rssv[k, 0];
      end_r = rssv[k, '"$samples"' - 1];
      start_s = swpv[k, 0];
      end_s = swpv[k, '"$samples"' - 1];
      delta = end_r - start_r;
      if (delta >= 5120) {
        print "| " a[1] " | " a[2] " | " a[3] " | " start_r " | " end_r " | " delta " | " start_s " | " end_s " |";
        found = 1;
      }
    }
  }
  if (!found) {
    print "| _none >= 5 MiB monotonic_ |  |  |  |  |  |  |  |";
  }
}
' "$series_tsv" > "$summary_md"

echo
echo "Done."
echo "Raw series: $series_tsv"
echo "System snapshots: $out_dir/system.txt"
echo "Summary: $summary_md"
