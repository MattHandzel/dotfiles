#!/usr/bin/env bash
# Restore the session saved by hyprland-session-save: relaunch each window's
# app on its original workspace. Terminals reopen in their saved cwd; a
# terminal that was running nvim reopens running nvim, and persistence.nvim
# then restores the buffers (auto-restore in notes dirs).
#
# Idempotent-ish: a class that already has an open window is skipped, so
# running this right after login won't duplicate autostarted apps.
set -uo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland-session/session.json"

notify() {
    command -v notify-send >/dev/null && notify-send -u normal "Session restore" "$1"
    echo "$1"
}

if [ ! -s "$STATE" ]; then
    notify "No saved session found at $STATE"
    exit 1
fi

existing_classes=$(hyprctl clients -j | jq -r '.[].class' | sort -u)

launched=0
skipped=0
unknown=""

while read -r entry; do
    class=$(jq -r '.class' <<<"$entry")
    ws=$(jq -r '.workspace' <<<"$entry")
    cwd=$(jq -r '.cwd // empty' <<<"$entry")
    nvim_cwd=$(jq -r '.nvim_cwd // empty' <<<"$entry")
    has_tmux=$(jq -r '.tmux // false' <<<"$entry")

    if grep -qxF "$class" <<<"$existing_classes"; then
        skipped=$((skipped + 1))
        continue
    fi

    cmd=""
    case "${class,,}" in
        kitty)
            if [ -n "$nvim_cwd" ] && [ -d "$nvim_cwd" ]; then
                # nvim with no args -> persistence.nvim restores the session
                cmd="kitty --directory $nvim_cwd -e nvim"
            elif [ "$has_tmux" = "true" ]; then
                # reattaches if the tmux server survived (hyprland restart);
                # after a reboot this is a fresh session
                cmd="kitty -e tmux -L hypr new-session"
            elif [ -n "$cwd" ] && [ -d "$cwd" ]; then
                cmd="kitty --directory $cwd"
            else
                cmd="kitty"
            fi
            ;;
        *)
            # org.foo.Bar -> bar; launch it if it's a real binary
            bin="${class,,}"
            bin="${bin##*.}"
            if command -v "$bin" >/dev/null 2>&1; then
                cmd="$bin"
            fi
            ;;
    esac

    if [ -z "$cmd" ]; then
        unknown="$unknown $class"
        continue
    fi

    hyprctl dispatch exec "[workspace $ws silent] $cmd" >/dev/null
    launched=$((launched + 1))
done < <(jq -c '.[]' "$STATE")

msg="Launched $launched window(s), skipped $skipped already open."
[ -n "$unknown" ] && msg="$msg No launcher known for:$unknown"
notify "$msg"
