# dayflow-export START END [DATE] [FPS] [EVERY]
#   dayflow-export 9:25 12:55                 today, 10 fps, one frame per 10 s
#   dayflow-export 14:00 16:30 2026-09-27 20
#   dayflow-export 14:00 14:10 "" 10 1        every frame (1 s apart since 10/06)
# Stitches Dayflow's screen recording between START and END (local time) into
# one shareable H.264 mp4 in ~/Movies and reveals it in Finder. Dayflow's UI
# only plays per-card previews; it has no range export.
#
# Dayflow stores HEVC chunks, one frame per screenshotIntervalSeconds of wall
# time (10 s until 2026-10-05; 1 s since 2026-10-06, Matt's rule, kept by
# dayflow-guard.nix), under recordings/, and indexes every frame in
# chunks.sqlite `screenshots`
# (captured_at, file_path, frame_index). Whole chunks are concatenated and the
# two ends are cut with `select` on the global frame number: the concat
# demuxer's inpoint/outpoint is not frame-accurate here (keyframes are 30
# frames apart; a 10-frame cut came out as 30).
# Timing: renumber frames at 1/FPS and keep the encoder on that timebase.
# With `-r` ffmpeg's CFR stage duplicated 9 frames (and trimmed the tail); with
# a default encoder timebase it rounded 0.1 s steps down to 1 s.
# Speed: keep one frame per EVERY s of wall time (default 10), so a video plays
# at the same speed whatever the capture cadence (1 s frames would otherwise
# make every export 10x longer). The step comes from the range's median gap.
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: dayflow-export START END [DATE] [FPS] [EVERY]   e.g. dayflow-export 9:25 12:55" >&2
  exit 2
fi
start=$1 end=$2 day=${3:-$(date +%Y-%m-%d)} fps=${4:-10} every=${5:-10}
db="$HOME/Library/Application Support/Dayflow/chunks.sqlite"
hhmm() { printf '%5s' "$1" | tr ' ' 0; }
start=$(hhmm "$start") end=$(hhmm "$end")

# One row per chunk: path|first frame_index in range|last frame_index in range
rows=$(sqlite3 "file:$db?mode=ro" "
  select file_path, min(frame_index), max(frame_index) from screenshots
  where is_deleted = 0
    and captured_at >= strftime('%s', '$day $start:00', 'utc')
    and captured_at <= strftime('%s', '$day $end:00', 'utc')
  group by file_path order by min(captured_at);")
if [ -z "$rows" ]; then
  echo "No Dayflow frames between $start and $end on $day" >&2
  exit 1
fi

# Median seconds between frames in the range -> keep every step-th frame.
gap=$(sqlite3 "file:$db?mode=ro" "
  select captured_at from screenshots where is_deleted = 0
    and captured_at >= strftime('%s', '$day $start:00', 'utc')
    and captured_at <= strftime('%s', '$day $end:00', 'utc') order by captured_at;" |
  awk 'NR > 1 { print $1 - p } { p = $1 }' | sort -n |
  awk '{ v[NR] = $1 } END { print (NR ? v[int((NR + 1) / 2)] : 10) }')
step=$(awk -v e="$every" -v g="$gap" 'BEGIN { s = int(e / (g > 0 ? g : 1) + 0.5); print (s < 1 ? 1 : s) }')

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
list=$tmp/list.txt
offset=0 first=-1 last=0
while IFS='|' read -r path lo hi; do
  [ -f "$path" ] || { echo "missing chunk: $path" >&2; continue; }
  [ "$first" -lt 0 ] && first=$lo
  last=$((offset + hi))
  printf "file '%s'\n" "${path//\'/\'\\\'\'}" >>"$list"
  n=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 "$path" </dev/null)
  offset=$((offset + n))
done <<<"$rows"

frames=$(((last - first) / step + 1))
mkdir -p "$HOME/Movies"
out="$HOME/Movies/dayflow-${day}_${start/:/}-${end/:/}.mp4"
ffmpeg -hide_banner -loglevel error -stats -y -f concat -safe 0 -i "$list" \
  -vf "select='between(n,$first,$last)*not(mod(n-$first,$step))',settb=1/$fps,setpts=N,fps=$fps:eof_action=pass" \
  -fps_mode passthrough -enc_time_base filter \
  -an -c:v libx264 -preset medium -crf 24 -pix_fmt yuv420p -movflags +faststart \
  -frames:v "$frames" "$out" </dev/null

echo "$out"
echo "$frames frames (${start}–${end} on $day, one per $((gap * step)) s of wall time), $((frames / fps)) s at $fps fps, $(du -h "$out" | cut -f1)"
open -R "$out" 2>/dev/null || true
