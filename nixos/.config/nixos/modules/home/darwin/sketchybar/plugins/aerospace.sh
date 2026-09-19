#!/usr/bin/env bash
# AeroSpace workspaces → one `space.<name>` item each.
#
# Shown: every workspace that has a window, plus the focused one. Focused is a
# Mauve pill with crust text — the single loud colour on the bar.
#
# A numbered workspace shows its digit (that is what alt-<n> jumps to). A named
# one (anki, calendar, …) shows only its app glyphs, because the word just
# restates the glyph and ate half the bar. That choice is made once, when the
# item is created, so a workspace never flips between word and glyph.
#
# Items are added and removed by DELTA only — an item that is staying is never
# removed and re-added, because that is what made the whole strip flash on
# every workspace switch. Ordering is done with --move, which does not destroy.
#
# Called on: aerospace_workspace_change (from ~/.aerospace.toml), on
# front_app_switched (a window moved), on a 30 s timer, and once at startup.

set +u  # empty arrays under bash 3.2 would trip -u
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
source "$CONFIG_DIR/colors.sh"
source "$CONFIG_DIR/plugins/icon_map.sh"

AEROSPACE=/opt/homebrew/bin/aerospace
SB=/opt/homebrew/bin/sketchybar
JQ=/opt/homebrew/bin/jq
FONT="JetBrainsMono Nerd Font"

focused="${FOCUSED_WORKSPACE:-$($AEROSPACE list-workspaces --focused 2>/dev/null)}"
[ -z "$focused" ] && exit 0

is_num() { printf '%s' "$1" | grep -qE '^[0-9]+$'; }
has()    { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# Numbered workspaces first (numerically), then named ones (alphabetically).
order_stable() {
  local all; all="$(sort -u)"
  printf '%s\n' "$all" | grep -E '^[0-9]+$' | sort -n
  printf '%s\n' "$all" | grep -vE '^[0-9]+$' | sort
}

# Desired set: every occupied workspace plus the focused one.
wanted=("$focused")
while IFS= read -r w; do [ -n "$w" ] && wanted+=("$w"); done \
  < <($AEROSPACE list-workspaces --monitor all --empty no 2>/dev/null)
tmp=(); while IFS= read -r w; do [ -n "$w" ] && tmp+=("$w"); done \
  < <(printf '%s\n' "${wanted[@]}" | order_stable)
wanted=("${tmp[@]}")

# Focus Mode (/tmp/focus_mode): a workspace whose name or any app on it matches
# the distracting list (focus-distracting-apps, from focus-mode-apps.md) gets no
# pill, so the bar is not a way in. The focused workspace always keeps its
# pill. Getting there by any route is gated (15 s) by ~/.hammerspoon/focus_gate.lua.
if [ -e /tmp/focus_mode ]; then
  re="$(/etc/profiles/per-user/"$(id -un)"/bin/focus-distracting-apps 2>/dev/null)"
  if [ -n "$re" ]; then
    tmp=()
    for w in "${wanted[@]}"; do
      if [ "$w" != "$focused" ] && { printf '%s\n' "$w"; $AEROSPACE list-windows --workspace "$w" --format '%{app-name}' 2>/dev/null; } | grep -qiE "$re"; then
        continue
      fi
      tmp+=("$w")
    done
    wanted=("${tmp[@]}")
  fi
fi

existing=(); while IFS= read -r w; do [ -n "$w" ] && existing+=("$w"); done \
  < <($SB --query bar 2>/dev/null | $JQ -r '.items[]' | grep '^space\.' | sed 's/^space\.//')

args=()

# Remove only what genuinely went away.
for w in "${existing[@]}"; do
  has "$w" "${wanted[*]}" || args+=(--remove "space.$w")
done

# Add only what is genuinely new.
for w in "${wanted[@]}"; do
  has "$w" "${existing[*]}" && continue
  if is_num "$w"; then icon_draw=on; label_pad=0; else icon_draw=off; label_pad=7; fi
  args+=(--add item "space.$w" left
         --set "space.$w"
           icon="$w"
           icon.drawing="$icon_draw"
           icon.font="$FONT:Bold:12.5"
           icon.padding_left=7
           icon.padding_right=2
           label.font="sketchybar-app-font:Regular:14.0"
           label.padding_left="$label_pad"
           label.padding_right=7
           label.y_offset=-1
           background.drawing=on
           background.height=21
           background.corner_radius=5
           padding_left=1
           padding_right=1
           click_script="$AEROSPACE $([ "$w" = oops ] && echo summon-workspace || echo workspace) $w")
done

# Order the whole strip. --move never destroys, so this cannot flash.
for w in "${wanted[@]}"; do args+=(--move "space.$w" before front_app); done
[ ${#args[@]} -gt 0 ] && $SB "${args[@]}"

# Recolour + refresh the app glyphs.
args=()
for w in "${wanted[@]}"; do
  glyphs=""
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    __icon_map "$app"
    glyphs+="${icon_result:-:default:}"
  done < <($AEROSPACE list-windows --workspace "$w" --format '%{app-name}' 2>/dev/null | sort -u)

  # A named workspace with nothing in it keeps a dot so the pill is not blank.
  if [ -z "$glyphs" ] && ! is_num "$w"; then glyphs="·"; fi

  if [ "$w" = "$focused" ]; then
    args+=(--set "space.$w"
             label="$glyphs"
             label.drawing=$([ -n "$glyphs" ] && echo on || echo off)
             icon.color="$CRUST" label.color="$CRUST"
             background.color="$MAUVE")
  else
    args+=(--set "space.$w"
             label="$glyphs"
             label.drawing=$([ -n "$glyphs" ] && echo on || echo off)
             icon.color="$SUBTEXT0" label.color="$SUBTEXT0"
             background.color="$SURFACE0")
  fi
done
[ ${#args[@]} -gt 0 ] && $SB "${args[@]}"
exit 0
