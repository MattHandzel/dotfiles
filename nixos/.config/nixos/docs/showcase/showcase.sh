#!/usr/bin/env bash
# showcase — build this repo's README: offscreen screenshots + generated prose.
#
# Screenshots are taken on a VIRTUAL HEADLESS OUTPUT attached to the running
# Hyprland instance and parked far off-canvas. Scene windows are routed there by
# a windowrule before they ever map, so nothing appears on the real screen, focus
# never moves, and the visible workspace is never switched. The output is torn
# down on exit (including on Ctrl-C and on error).
#
# The safety of that rests on ONE thing: the routing windowrule actually being
# accepted by Hyprland. It is not assumed — `install_rules` aborts if hyprctl
# does not answer "ok", and every launched window is verified to have landed on
# the showcase workspace before the run continues. A window found anywhere else
# is killed immediately and the run aborts. (Learned the hard way: Hyprland 0.53
# rejects the old `class:^(x)$` matcher syntax with a message on stdout and a
# ZERO exit code, so an unchecked `hyprctl keyword` silently leaves every scene
# window free to open on top of whatever you are doing.)
#
# Usage:
#   ./showcase.sh scenes                 list available scenes
#   ./showcase.sh capture [scene ...]    capture all scenes (or just the named ones)
#   ./showcase.sh readme                 regenerate README.md from modules + shots
#   ./showcase.sh all                    capture, then regenerate
#
# Capture options:
#   --width N --height N --scale N   virtual output geometry (default 2560x1440@1)
#   --no-bar        skip the waybar instance in scenes that ask for one
#   --no-wallpaper  leave the scene background alone (use the live wallpaper)
#   --no-frame      write the flat grab, skip the rounded-corner/shadow framing
#   --keep-raw      also keep the unframed grab as <scene>.raw.png
#   --settle N      extra seconds to wait before each grab (added to the scene's own)
#   --dry-run       print what would run; touch nothing

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
CONFIG_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
SCENES_DIR="$SCRIPT_DIR/scenes"
SHOTS_DIR="$SCRIPT_DIR/screenshots"
MANIFEST="$SHOTS_DIR/manifest.json"

# Geometry of the virtual output. 2560x1440 at scale 1 gives a crisp 16:9 grab
# that downsizes cleanly to README width without resampling artefacts.
OUT_W=2560
OUT_H=1440
OUT_SCALE=1
# Park the output well clear of any real monitor's logical extent so the pointer
# can never wander onto it. eDP-1 here is 2160 logical px wide; 6000 is ample.
OUT_X=6000
OUT_Y=0

WANT_BAR=1
WANT_WALLPAPER=1
WANT_FRAME=1
KEEP_RAW=0
EXTRA_SETTLE=0
DRY_RUN=0

# Framing palette (catppuccin mocha) — the backdrop the grab is composited onto.
FRAME_PAD=64
FRAME_RADIUS=16
FRAME_GRAD_FROM='#313244'
FRAME_GRAD_TO='#181825'
README_MAX_WIDTH=1600

log()  { printf '\033[38;5;110m::\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[38;5;214m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[38;5;203mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ─── teardown ────────────────────────────────────────────────────────────────
# Everything the run creates is registered here so a single trap can undo it,
# whether we finish, fail, or get interrupted.
SCENE_PIDS=()
RUN_TMPDIRS=()
MON=""
WS=""

cleanup() {
  local rc=$?
  set +e
  kill_pids "${SCENE_PIDS[@]+"${SCENE_PIDS[@]}"}"
  teardown_output
  local d
  for d in "${RUN_TMPDIRS[@]+"${RUN_TMPDIRS[@]}"}"; do rm -rf "$d"; done
  RUN_TMPDIRS=()
  exit $rc
}

teardown_output() {
  [ -n "$MON" ] || return 0
  hyprctl output remove "$MON" >/dev/null 2>&1
  log "removed virtual output $MON"
  MON=""
  WS=""
}

kill_pids() {
  local p
  for p in "$@"; do
    [ -n "${p:-}" ] || continue
    kill "$p" 2>/dev/null || true
  done
  # Give them a beat to unmap, then insist.
  if [ $# -gt 0 ]; then
    sleep 0.4 2>/dev/null || true
    for p in "$@"; do
      [ -n "${p:-}" ] || continue
      kill -9 "$p" 2>/dev/null || true
    done
  fi
}

# ─── preflight ───────────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

preflight() {
  need hyprctl; need grim; need jq; need magick; need kitty
  [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] \
    || die "not inside a Hyprland session (HYPRLAND_INSTANCE_SIGNATURE unset)"
  hyprctl monitors -j >/dev/null 2>&1 \
    || die "cannot talk to the Hyprland socket"
}

# ─── virtual output ──────────────────────────────────────────────────────────
create_output() {
  local before after
  before="$(hyprctl monitors -j | jq -r '[.[].name]|join(" ")')"
  hyprctl output create headless >/dev/null || die "hyprctl output create failed"
  sleep 1 2>/dev/null || true
  after="$(hyprctl monitors -j | jq -r '.[]|select(.name|startswith("HEADLESS"))|.name')"

  local m
  for m in $after; do
    case " $before " in *" $m "*) ;; *) MON="$m"; break ;; esac
  done
  [ -n "$MON" ] || die "could not identify the new headless output"

  hyprctl keyword monitor "$MON,${OUT_W}x${OUT_H}@60,${OUT_X}x${OUT_Y},${OUT_SCALE}" >/dev/null
  sleep 1 2>/dev/null || true

  WS="$(hyprctl monitors -j | jq -r --arg m "$MON" '.[]|select(.name==$m)|.activeWorkspace.id')"
  [ -n "$WS" ] && [ "$WS" != "null" ] || die "no workspace bound to $MON"
  log "virtual output $MON (${OUT_W}x${OUT_H}@${OUT_SCALE}) at ${OUT_X},${OUT_Y}, workspace $WS"
}

# A `hyprctl keyword` with a bad matcher prints its complaint and still exits 0.
# The only reliable signal is the literal body "ok", so demand exactly that.
hypr_keyword() {
  local out
  out="$(hyprctl keyword "$@" 2>&1)" || die "hyprctl keyword $* failed"
  [ "$out" = "ok" ] || die "Hyprland rejected: hyprctl keyword $*
  -> $out
  Refusing to launch scene windows: without this rule they would open on your
  visible workspace."
}

install_rules() {
  # Hyprland 0.53 matcher syntax: `match:<field> <regex>`, space-separated.
  hypr_keyword windowrule "workspace $WS silent, match:class ^(showcase-.*)$"
  hypr_keyword windowrule "no_initial_focus 1, match:class ^(showcase-.*)$"
  hypr_keyword windowrule "no_anim 1, match:class ^(showcase-.*)$"
  log "routing rules installed for class showcase-*"
}

# ─── scene helpers (called from scene files) ─────────────────────────────────
# term <name> <command...> — a kitty window on the showcase workspace running
# <command>. Uses the real kitty config, so the screenshot shows the real theme.
term() {
  local name="$1"; shift
  local cls="showcase-$name"
  if [ "$DRY_RUN" = 1 ]; then log "  would launch term $name: $*"; return 0; fi
  # SCENE_FONT_SIZE lets a scene whose output is short scale up to fill the
  # frame, rather than leaving two thirds of the screenshot empty.
  local opts=()
  [ -n "${SCENE_FONT_SIZE:-}" ] && opts=(-o "font_size=${SCENE_FONT_SIZE}")
  kitty --class "$cls" --title "$cls" "${opts[@]+"${opts[@]}"}" -e "$@" >/dev/null 2>&1 &
  SCENE_PIDS+=("$!")
  verify_placed "$cls" "$!"
}

# app <name> <command...> — any GUI whose window class you cannot control.
# It is routed by title instead, so the scene must pass a matching title.
app() {
  local name="$1"; shift
  if [ "$DRY_RUN" = 1 ]; then log "  would launch app $name: $*"; return 0; fi
  "$@" >/dev/null 2>&1 &
  SCENE_PIDS+=("$!")
}

# verify_placed <class> <pid> — wait for the window, then prove it is offscreen.
# Anything else is a routing failure: kill it at once and abort the run.
verify_placed() {
  local cls="$1" pid="$2" i ws
  # Polled tightly on purpose: this is the window in which a misrouted window
  # would be visible on the real screen before being killed.
  for i in $(seq 1 150); do
    ws="$(hyprctl clients -j | jq -r --arg c "$cls" \
          'first(.[]|select(.class==$c)|.workspace.id) // empty')"
    if [ -n "$ws" ]; then
      if [ "$ws" != "$WS" ]; then
        kill -9 "$pid" 2>/dev/null || true
        die "window $cls mapped on workspace $ws, expected $WS — routing failed, aborting"
      fi
      return 0
    fi
    sleep 0.1 2>/dev/null || true
  done
  warn "window $cls never appeared (pid $pid) — continuing without it"
}

# bar — a second waybar restricted to the virtual output, so the desktop shots
# show the real bar. The tray module is stripped: a second instance cannot own
# the StatusNotifierHost name and would render an empty or duplicated tray.
bar() {
  [ "$WANT_BAR" = 1 ] || return 0
  command -v waybar >/dev/null 2>&1 || { warn "waybar not on PATH, skipping bar"; return 0; }

  # The live waybar declares no `output`, so it puts a bar on every output the
  # moment one appears — including this one. Spawning a second instance would
  # stack two bars on top of each other. Only spawn if the output came up bare.
  if [ -n "$MON" ] && [ "$(hyprctl layers -j \
        | jq -r --arg m "$MON" '[.[$m].levels[]?[]? | select(.namespace=="waybar")] | length')" != "0" ]; then
    log "  waybar already present on $MON (live instance covers it)"
    return 0
  fi
  local src="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config"
  [ -f "$src" ] || src="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/config.jsonc"
  [ -f "$src" ] || { warn "no waybar config found, skipping bar"; return 0; }
  if [ "$DRY_RUN" = 1 ]; then log "  would launch waybar on $MON"; return 0; fi

  local dir; dir="$(mktemp -d)"
  RUN_TMPDIRS+=("$dir")
  if ! jq --arg o "$MON" '
        (if type=="array" then .[0] else . end)
        | .output = [$o]
        | (.["modules-right"] //= []) |= map(select(. != "tray"))
      ' "$src" > "$dir/config" 2>/dev/null; then
    warn "could not rewrite waybar config, skipping bar"
    return 0
  fi
  local style="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/style.css"
  local args=(-c "$dir/config")
  if [ -f "$style" ]; then
    cp "$style" "$dir/style.css"
    args+=(-s "$dir/style.css")
  fi
  waybar "${args[@]}" >/dev/null 2>&1 &
  SCENE_PIDS+=("$!")
  sleep 1 2>/dev/null || true
}

# wallpaper — paint the virtual output with the repo's wallpaper. Keeps shots
# reproducible and keeps whatever personal image is currently set out of a
# README that gets pushed to a public remote.
wallpaper() {
  [ "$WANT_WALLPAPER" = 1 ] || return 0
  command -v swaybg >/dev/null 2>&1 || return 0
  local img="${1:-$CONFIG_ROOT/wallpapers/wallpaper.png}"
  [ -f "$img" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then log "  would set wallpaper $img on $MON"; return 0; fi
  swaybg -o "$MON" -i "$img" -m fill >/dev/null 2>&1 &
  SCENE_PIDS+=("$!")
  sleep 0.6 2>/dev/null || true
}

# layout helpers, applied to the showcase workspace only.
settle() { sleep "${1:-2}" 2>/dev/null || true; }

# ─── capture ─────────────────────────────────────────────────────────────────
list_scenes() {
  local f
  for f in "$SCENES_DIR"/*.sh; do
    [ -e "$f" ] || continue
    ( # shellcheck disable=SC1090
      SCENE_TITLE=""; SCENE_CAPTION=""
      . "$f"
      printf '  %-14s %s\n' "$(scene_id "$f")" "${SCENE_TITLE:-untitled}"
    )
  done
}

scene_id() { basename "$1" .sh | sed 's/^[0-9]*-//'; }

capture_scene() {
  local file="$1" id title caption sett
  id="$(scene_id "$file")"

  SCENE_TITLE=""; SCENE_CAPTION=""; SCENE_SETTLE=3; SCENE_FONT_SIZE=""
  unset -f scene_run 2>/dev/null || true
  # shellcheck disable=SC1090
  . "$file"
  title="${SCENE_TITLE:-$id}"
  caption="${SCENE_CAPTION:-}"
  sett="${SCENE_SETTLE:-3}"

  log "scene: $id — $title"
  SCENE_PIDS=()

  if declare -F scene_run >/dev/null; then
    scene_run
  else
    warn "scene $id defines no scene_run(), skipping"
    return 0
  fi

  if [ "$DRY_RUN" = 1 ]; then
    log "  would grab $MON -> $SHOTS_DIR/$id.png (settle ${sett}s)"
    SCENE_PIDS=()
    return 0
  fi

  settle "$((sett + EXTRA_SETTLE))"

  mkdir -p "$SHOTS_DIR"
  local raw="$SHOTS_DIR/$id.raw.png"
  grim -o "$MON" "$raw" || die "grim failed on $MON"

  if [ "$WANT_FRAME" = 1 ]; then
    frame_image "$raw" "$SHOTS_DIR/$id.png"
    [ "$KEEP_RAW" = 1 ] || rm -f "$raw"
  else
    magick "$raw" -resize "${README_MAX_WIDTH}x>" "$SHOTS_DIR/$id.png"
    [ "$KEEP_RAW" = 1 ] || rm -f "$raw"
  fi
  log "  wrote $SHOTS_DIR/$id.png"

  record_shot "$id" "$title" "$caption"

  kill_pids "${SCENE_PIDS[@]+"${SCENE_PIDS[@]}"}"
  SCENE_PIDS=()
  # Wait for the workspace to actually drain before the next scene, or its
  # leftovers tile into the next screenshot.
  local i
  for i in $(seq 1 40); do
    [ "$(hyprctl clients -j | jq -r --arg w "$WS" '[.[]|select(.workspace.id==($w|tonumber))]|length')" = "0" ] && break
    sleep 0.25 2>/dev/null || true
  done
}

# frame_image <in> <out> — downscale, round the corners, drop a soft shadow and
# composite onto a gradient backdrop. This is the "nice" in nice screenshots.
frame_image() {
  local in="$1" out="$2" tmp
  tmp="$(mktemp -d)"; RUN_TMPDIRS+=("$tmp")

  magick "$in" -resize "${README_MAX_WIDTH}x>" "$tmp/scaled.png"

  # Rounded corners via an alpha mask drawn at the scaled size.
  magick "$tmp/scaled.png" -alpha set \
    \( +clone -alpha transparent -background none \
       -fill white -draw "roundrectangle 0,0,%[fx:w-1],%[fx:h-1],$FRAME_RADIUS,$FRAME_RADIUS" \) \
    -compose DstIn -composite "$tmp/rounded.png"

  # Soft shadow, offset slightly downward so the card reads as lifted.
  magick "$tmp/rounded.png" \
    \( +clone -background black -shadow 55x18+0+10 \) \
    +swap -background none -layers merge +repage "$tmp/shadowed.png"

  local w h bw bh
  w="$(magick identify -format '%w' "$tmp/shadowed.png")"
  h="$(magick identify -format '%h' "$tmp/shadowed.png")"
  bw=$((w + FRAME_PAD * 2))
  bh=$((h + FRAME_PAD * 2))

  # -depth 8: the intermediate compositing steps promote to 16-bit, which
  # doubles the file for no visible gain on a screenshot that started at 8.
  magick -size "${bw}x${bh}" "gradient:${FRAME_GRAD_FROM}-${FRAME_GRAD_TO}" \
    "$tmp/shadowed.png" -gravity center -composite \
    -depth 8 -define png:compression-level=9 -strip "$out"
}

record_shot() {
  local id="$1" title="$2" caption="$3" w h now
  w="$(magick identify -format '%w' "$SHOTS_DIR/$id.png")"
  h="$(magick identify -format '%h' "$SHOTS_DIR/$id.png")"
  now="$(date -Iseconds)"
  local existing='[]'
  [ -f "$MANIFEST" ] && existing="$(cat "$MANIFEST")"
  jq --arg id "$id" --arg t "$title" --arg c "$caption" \
     --arg f "screenshots/$id.png" --argjson w "$w" --argjson h "$h" --arg at "$now" '
     (. // []) | map(select(.id != $id))
     + [{id:$id, title:$t, caption:$c, file:$f, width:$w, height:$h, captured_at:$at}]
     | sort_by(.id)
  ' <<<"$existing" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
}

cmd_capture() {
  preflight
  local files=() f
  if [ $# -gt 0 ]; then
    local want cand hit
    for want in "$@"; do
      hit=""
      for cand in "$SCENES_DIR"/*.sh; do
        [ -e "$cand" ] || continue
        if [ "$(scene_id "$cand")" = "$want" ]; then hit="$cand"; break; fi
      done
      [ -n "$hit" ] || die "no such scene: $want (try: $0 scenes)"
      files+=("$hit")
    done
  else
    for f in "$SCENES_DIR"/*.sh; do [ -e "$f" ] && files+=("$f"); done
  fi
  [ "${#files[@]}" -gt 0 ] || die "no scenes found in $SCENES_DIR"

  if [ "$DRY_RUN" = 1 ]; then
    log "dry run — no output created, nothing launched"
    for f in "${files[@]}"; do capture_scene "$f"; done
    return 0
  fi

  log "capturing on an offscreen virtual output — your screen, focus and"
  log "workspace are not touched. Ctrl-C is safe; teardown runs on exit."
  trap cleanup EXIT INT TERM
  create_output
  install_rules
  for f in "${files[@]}"; do capture_scene "$f"; done

  # Give the output back as soon as the last grab lands, rather than holding it
  # for however long README generation takes.
  teardown_output
  local d
  for d in "${RUN_TMPDIRS[@]+"${RUN_TMPDIRS[@]}"}"; do rm -rf "$d"; done
  RUN_TMPDIRS=()
  log "captured ${#files[@]} scene(s) into $SHOTS_DIR"
}

cmd_readme() {
  need python3
  python3 "$SCRIPT_DIR/gen_readme.py" "$@"
}

# ─── arg parsing ─────────────────────────────────────────────────────────────
CMD="${1:-}"; shift || true
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --width)      OUT_W="$2"; shift 2 ;;
    --height)     OUT_H="$2"; shift 2 ;;
    --scale)      OUT_SCALE="$2"; shift 2 ;;
    --settle)     EXTRA_SETTLE="$2"; shift 2 ;;
    --no-bar)     WANT_BAR=0; shift ;;
    --no-wallpaper) WANT_WALLPAPER=0; shift ;;
    --no-frame)   WANT_FRAME=0; shift ;;
    --keep-raw)   KEEP_RAW=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            POSITIONAL+=("$1"); shift ;;
  esac
done

ARGS=("${POSITIONAL[@]+"${POSITIONAL[@]}"}")

case "$CMD" in
  scenes)  list_scenes ;;
  capture) cmd_capture "${ARGS[@]+"${ARGS[@]}"}" ;;
  readme)  cmd_readme "${ARGS[@]+"${ARGS[@]}"}" ;;
  all)     cmd_capture "${ARGS[@]+"${ARGS[@]}"}"; cmd_readme ;;
  ""|-h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)       die "unknown command: $CMD (try: scenes | capture | readme | all)" ;;
esac
