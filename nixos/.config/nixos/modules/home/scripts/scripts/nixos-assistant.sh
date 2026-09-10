#!/usr/bin/env bash
# nixos-assistant — a Claude Code harness for editing this NixOS flake fast.
# Bound to SUPER+grave (Hyprland). Run from anywhere; it always lands in the repo.
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

# Resolve the claude binary to an absolute path, PREFERRING the npm install.
# Order matters and is load-bearing: a nixpkgs `claude-code` on PATH is typically
# many minor versions behind npm, and the CLI's accepted --permission-mode values
# change between them (2.1.39 has no `auto`; 2.1.219 does). Login shells prepend
# ~/.npm-packages/bin so they never saw the old one, but Hyprland's exec
# environment does not — so hotkey launches picked up the stale binary, which
# rejected the flag below and exited 1 before the UI ever drew. Ask for the npm
# binary by name first; only fall back to PATH if it is absent.
CLAUDE="$HOME/.npm-packages/bin/claude"
[[ -x "$CLAUDE" ]] || CLAUDE="$(command -v claude 2>/dev/null || true)"
if [[ -z "$CLAUDE" || ! -x "$CLAUDE" ]]; then
  echo "nixos-assistant: no claude binary found (looked in ~/.npm-packages/bin and PATH)" >&2
  command -v notify-send >/dev/null 2>&1 &&
    notify-send -u critical "nixos-assistant" "No claude binary found"
  exit 1
fi

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

# The focused operating brief layered on top of the repo's CLAUDE.md.
#
# The numbered rules are not generic advice — each one was mined from this
# repo's own session transcripts, where it cost Matt real time (espanso patched
# and re-patched a dozen times, focus mode "fixed" without ever being run, a
# rebuild owed but never applied). Keep them concrete; delete one only when the
# transcripts stop showing it.
read -r -d '' SYS_PROMPT <<'EOF' || true
You are Matt's NixOS configuration assistant, running inside his flake repo
(~/dotfiles/nixos/.config/nixos). The active host is given in the first message.

Work declaratively: prefer flake/Home-Manager options over imperative state, keep
changes minimal and scoped to the request, format every Nix file with alejandra,
and validate with `nix flake check`. On the `laptop` host you ARE allowed to apply
changes yourself — `hm-switch` for home-only changes, `sudo nixos-rebuild
test|switch --flake .#laptop` for system ones. NixOS generations make this safe
(Matt can always boot a previous generation), so apply when asked instead of
deferring. The launcher also rebuilds on exit.

Keep a live todo list. Call TaskCreate the moment the work has more than one part,
and again the moment Matt adds a request mid-turn; TaskUpdate as each part lands.
He routinely stacks requests while you are working, and a request that never
became a task is a request you will drop. Finish every item, or state plainly
which ones you did not and why.

These are the failure modes that have actually cost Matt time in this repo. They
are hard rules, not suggestions:

1. Verify, don't assert. Never report a fix without running the real path a human
   would use, and pasting the output. A green build, `systemctl is-active`, and
   "the config looks correct" are not evidence — the evidence is the app actually
   launching, the trigger actually expanding, the script actually printing. If you
   cannot exercise the real path, say so rather than implying you did.
2. Root cause, not band-aid. Matt keeps having to say "solve the root problem"
   because patches here re-break. State the mechanism you found before you change
   anything, and fix that mechanism.
3. A repeat report means your previous fix was wrong. When he says "still",
   "again", or "I've told you N times", do not re-apply a variant of the same fix.
   Restart from observation, and record what you learned in
   ~/.claude/projects/-home-matth-dotfiles/memory/ so the next session inherits it.
4. A runtime workaround is not done. A manual systemctl call or hand-edited file
   fixes this boot only. It is finished when it lives in the flake and survives a
   rebuild — and you have rebuilt to show that it does.
5. Treat Matt's ruled-out causes as ruled out. If he says power is not the issue,
   believe him and look elsewhere instead of re-proposing it.
6. Do only what was asked. Do not start adjacent work he did not request.

End your turn with a one-line summary of what changed and how it was verified.
EOF

# --- claude mode: the actual session, run as the tmux window's command --------
# Kept separate so tmux can exec it without any quoting of the (possibly
# multi-line) request — everything crosses the boundary via the environment.
if [[ "${1:-}" == "--claude" ]]; then
  cd "$REPO" || exit 1
  HOST="$(resolve_host)"
  args=(--permission-mode auto)
  args+=(--chrome)
  # A rejected flag (see the CLAUDE resolution above) kills the session before it
  # renders, and inside tmux the pane vanishes with the error. Keep the message
  # on screen so the failure is legible instead of looking like a phantom crash.
  die_visibly() {
    printf '\n\033[1;31mnixos-assistant: claude exited immediately (%s)\033[0m\n' "$1" >&2
    printf '  binary: %s\n' "$CLAUDE" >&2
    printf '\n\033[2m(press enter to close)\033[0m' >&2
    read -r
    exit 1
  }

  if [[ -n "${NIXOS_ASSISTANT_REQUEST:-}" ]]; then
    args+=(--append-system-prompt "$SYS_PROMPT")
    "$CLAUDE" "${args[@]}" "Active host: ${HOST}. ${NIXOS_ASSISTANT_REQUEST}"
  else
    args+=(--append-system-prompt "$SYS_PROMPT (Active host: ${HOST}.)")
    "$CLAUDE" "${args[@]}"
  fi
  rc=$?
  # Only a *failed* start is worth holding the pane open for; a clean exit is the
  # normal way out of the session and must fall through to the rebuild menu.
  ((rc != 0)) && die_visibly "exit $rc"
  exit 0
fi

# --- inner mode: runs *inside* the floating terminal -------------------------
# Manages the tmux session (attach or create), then shows the rebuild menu when
# the user exits or detaches — in the same window they're already looking at.
if [[ "${1:-}" == "--inner" ]]; then
  HOST="$(resolve_host)"
  SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
  tx() { tmux -L "$TMUX_SOCK" "$@"; }

  session_start=$SECONDS
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

  # A session that ended in seconds did not end because Matt finished working —
  # it crashed on startup. Auto-rebuilding on that path is the worst possible
  # response: it would `git add --all` and `nixos-rebuild switch` an untouched
  # (or half-edited) tree with nobody watching, triggered by a failure. Bail out
  # and say why instead. 15s is comfortably above any real crash and far below
  # any real session.
  if ((SECONDS - session_start < 15)); then
    printf '\n\033[1;31m── nixos-assistant ──\033[0m the Claude session exited after %ds.\n' \
      "$((SECONDS - session_start))"
    printf '  That is a startup failure, not a finished session — skipping the rebuild.\n'
    printf '  Reproduce the error with:  \033[1m%s --permission-mode auto --chrome\033[0m\n' "$CLAUDE"
    printf '\n\033[2m(press enter to close)\033[0m'
    read -r
    exit 1
  fi

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
