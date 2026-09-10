#!/usr/bin/env bash
# Snapshot the current Hyprland session (windows, workspaces, terminal cwds,
# and whether a terminal is running nvim) so hyprland-session-restore can
# bring it back after a reboot or Hyprland crash.
#
# Runs from a systemd user timer (see modules/home/hyprland/hyprsession.nix)
# and can also be invoked manually.
set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland-session"
mkdir -p "$STATE_DIR"
OUT="$STATE_DIR/session.json"

# systemd user services don't inherit HYPRLAND_INSTANCE_SIGNATURE; derive it
# from the runtime dir so hyprctl works.
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    sig=$(ls -t "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null | head -1)
    [ -n "$sig" ] && export HYPRLAND_INSTANCE_SIGNATURE="$sig"
fi

clients=$(hyprctl clients -j 2>/dev/null) || exit 0
count=$(jq '[.[] | select(.mapped and .workspace.id > 0)] | length' <<<"$clients" 2>/dev/null) || exit 0
# Don't clobber a good snapshot with an empty one (e.g. mid-logout)
[ "${count:-0}" -lt 1 ] && exit 0

list_descendants() {
    local children
    children=$(pgrep -P "$1" 2>/dev/null) || return 0
    local c
    for c in $children; do
        echo "$c"
        list_descendants "$c"
    done
}

tmp=$(mktemp "$STATE_DIR/.session.XXXXXX")
trap 'rm -f "$tmp"' EXIT

while read -r client; do
    pid=$(jq -r '.pid' <<<"$client")
    cwd=""
    nvim_cwd=""
    has_tmux=false
    for p in $(list_descendants "$pid"); do
        comm=$(cat "/proc/$p/comm" 2>/dev/null) || continue
        case "$comm" in
            nvim)
                [ -z "$nvim_cwd" ] && nvim_cwd=$(readlink "/proc/$p/cwd" 2>/dev/null || true)
                ;;
            tmux*) has_tmux=true ;;
            zsh | bash | fish)
                [ -z "$cwd" ] && cwd=$(readlink "/proc/$p/cwd" 2>/dev/null || true)
                ;;
        esac
    done
    jq -c --arg cwd "$cwd" --arg nvim_cwd "$nvim_cwd" --argjson tmux "$has_tmux" \
        '. + {cwd: $cwd, nvim_cwd: $nvim_cwd, tmux: $tmux}' <<<"$client" >>"$tmp"
done < <(jq -c '.[] | select(.mapped and .workspace.id > 0)
    | {class, title, workspace: .workspace.id, floating, pid}' <<<"$clients")

# Atomic replace; keep one backup generation
[ -f "$OUT" ] && cp "$OUT" "$OUT.bak"
jq -s '.' "$tmp" >"$OUT"
