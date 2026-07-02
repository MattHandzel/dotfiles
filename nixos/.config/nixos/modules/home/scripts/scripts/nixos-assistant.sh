#!/usr/bin/env bash
# nixos-assistant — a Claude Code harness for editing this NixOS flake fast.
# Bound to SUPER+period (Hyprland). Run from anywhere; it always lands in the repo.
#
# Why this exists: the bottleneck for system changes is the round-trip
# (open terminal → cd → recall the rebuild incantation → validate). This
# collapses that into one keypress: a floating Claude session in the flake,
# pre-primed with the repo's conventions, that offers a validated rebuild when
# you're done.
#
# The session runs inside tmux (dedicated socket), so it's persistent: close the
# window and the session keeps running; press the hotkey again to reattach to the
# same conversation. A fresh request given while a session is alive is pasted
# into the running session instead of starting over.
#
# Flow:
#   1. (optional) ask for a one-line request — leave blank to just drop into
#      an interactive session.
#   2. open a floating kitty in the flake; inside it, attach to (or create) a
#      tmux session running Claude (skip-permissions, primed system prompt).
#   3. on exit/detach, offer: flake check / rebuild test / rebuild switch —
#      with desktop notifications, never switching without an explicit choice.
#
# This is the only script that should run `nixos-rebuild switch` from a hotkey,
# and only after you pick it from the exit menu.
set -uo pipefail

REPO="$HOME/dotfiles/nixos/.config/nixos"
TITLE="nixos-assistant"
TMUX_SOCK="nixos-assistant"
TMUX_SESSION="nixos-assistant"

# Resolve the claude binary to an absolute path. Hyprland's exec environment may
# not include the npm bin dir on PATH, so fall back to the known install path.
CLAUDE="$(command -v claude 2>/dev/null || echo "$HOME/.npm-packages/bin/claude")"

# Resolve the target host: honour an override, else the machine's hostname if it
# maps to a real host dir, else fall back to the primary laptop.
resolve_host() {
  local h="${NIXOS_HOST:-$(hostname 2>/dev/null)}"
  if [[ -n "$h" && -d "$REPO/hosts/$h" ]]; then
    printf '%s' "$h"
  else
    printf 'laptop'
  fi
}

# The focused operating brief layered on top of the repo's CLAUDE.md. Keeps the
# session scoped and reinforces the one hard boundary: Claude validates, the
# launcher rebuilds.
read -r -d '' SYS_PROMPT <<'EOF' || true
You are Matt's NixOS configuration assistant, running inside his flake repo
(~/dotfiles/nixos/.config/nixos). The active host is given in the first message.
Work declaratively: prefer flake/Home-Manager options over imperative state,
keep changes minimal and scoped to the request, and format every Nix file with
alejandra. Before claiming a change is done, validate it with `nix flake check`
or a dry build (`nixos-rebuild dry-build --flake .#<host>`). On the `laptop`
host you ARE allowed to apply changes yourself with `sudo nixos-rebuild test`
or `sudo nixos-rebuild switch --flake .#laptop` — NixOS generations make this
safe (Matt can always boot a previous version), so run it when asked to
rebuild/test instead of deferring. The launcher also offers a rebuild on exit.
End your turn with a one-line summary of what changed and whether it validated.
EOF

# --- claude mode: the actual session, run as the tmux window's command --------
# Kept separate so tmux can exec it without any quoting of the (possibly
# multi-line) request — everything crosses the boundary via the environment.
if [[ "${1:-}" == "--claude" ]]; then
  cd "$REPO" || exit 1
  HOST="$(resolve_host)"
  args=(--dangerously-skip-permissions)
  if [[ -n "${NIXOS_ASSISTANT_REQUEST:-}" ]]; then
    args+=(--append-system-prompt "$SYS_PROMPT")
    exec "$CLAUDE" "${args[@]}" "Active host: ${HOST}. ${NIXOS_ASSISTANT_REQUEST}"
  else
    args+=(--append-system-prompt "$SYS_PROMPT (Active host: ${HOST}.)")
    exec "$CLAUDE" "${args[@]}"
  fi
fi

# --- inner mode: runs *inside* the floating terminal -------------------------
# Manages the tmux session (attach or create), then shows the rebuild menu when
# the user exits or detaches — in the same window they're already looking at.
if [[ "${1:-}" == "--inner" ]]; then
  HOST="$(resolve_host)"
  SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
  tx() { tmux -L "$TMUX_SOCK" "$@"; }

  if ! command -v tmux >/dev/null 2>&1; then
    echo "tmux not found; running claude directly." >&2
    NIXOS_ASSISTANT_REQUEST="${NIXOS_ASSISTANT_REQUEST:-}" bash "$SELF" --claude
  elif tx has-session -t "$TMUX_SESSION" 2>/dev/null; then
    # Reattach to the live session. If a new request was given, paste it into
    # the running Claude and submit it, rather than starting over.
    if [[ -n "${NIXOS_ASSISTANT_REQUEST:-}" ]]; then
      # The session may be mid-prompt: when Claude is showing a question or a
      # selection menu, that menu holds the key focus, so a plain paste is
      # swallowed (and the trailing Enter just picks a menu item) — the new
      # message is lost. Escape first to drop back to the normal text input,
      # then deliver the request as literal keystrokes (more reliable than
      # paste-buffer across input modes) and submit it.
      tx send-keys -t "$TMUX_SESSION" Escape
      sleep 0.3
      tx send-keys -t "$TMUX_SESSION" -l "$NIXOS_ASSISTANT_REQUEST"
      sleep 0.3
      tx send-keys -t "$TMUX_SESSION" Enter
    fi
    tx attach -t "$TMUX_SESSION"
  else
    # Fresh session. The request crosses into --claude via the environment.
    tx new-session -s "$TMUX_SESSION" -c "$REPO" -- bash "$SELF" --claude
  fi

  # --- automatic rebuild ------------------------------------------------------
  # On exit/detach, rebuild the host automatically. A short cancel window guards
  # against an accidental rebuild while letting the common case be hands-free.
  cd "$REPO" || exit 1
  notify() { command -v notify-send >/dev/null 2>&1 && notify-send -t 3000 -i dialog-information "$@"; }

  printf '\n\033[1;35m── nixos-assistant ──\033[0m  host: \033[1m%s\033[0m\n' "$HOST"
  printf '  rebuilding (switch) in 3s…  \033[2m[c] cancel · [t] test instead\033[0m\n'
  choice=""
  read -r -t 3 -n1 choice || true
  printf '\n'

  if [[ "$choice" == "c" || "$choice" == "C" ]]; then
    printf 'cancelled — tmux session kept; press the hotkey again to reattach.\n'
  else
    mode="switch"
    [[ "$choice" == "t" || "$choice" == "T" ]] && mode="test"
    notify "NixOS rebuild" "${mode} → .#${HOST} 👷"
    git add --all .
    if sudo nixos-rebuild "$mode" --flake ".#${HOST}"; then
      notify "NixOS rebuild" "${mode} succeeded ✅"
    else
      notify "NixOS rebuild" "${mode} FAILED ❌ — review output above"
    fi
  fi

  printf '\n\033[2m(press enter to close)\033[0m'
  read -r
  exit 0
fi

# --- outer mode: gather request and launch the floating terminal -------------
request="$*"
if [[ -z "$request" ]]; then
  # No CLI arg: offer a quick GUI entry. Blank/OK = interactive session.
  if command -v zenity >/dev/null 2>&1; then
    request=$(zenity --entry \
      --title="nixos-assistant" \
      --text="What should Claude change in your NixOS config?  (leave blank for an interactive session)" \
      --width=560 2>/dev/null) || exit 0
  fi
fi

# Trim surrounding whitespace.
request="${request#"${request%%[![:space:]]*}"}"
request="${request%"${request##*[![:space:]]}"}"

export NIXOS_ASSISTANT_REQUEST="$request"
SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
exec kitty --title "$TITLE" --working-directory "$REPO" -e bash "$SELF" --inner
