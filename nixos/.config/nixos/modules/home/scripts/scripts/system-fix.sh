#!/usr/bin/env bash
# system-fix — hotkey-launched Claude Code session for fixing bugs and adding
# features in this NixOS + Home Manager + Hyprland dotfiles repo.
# Bound to SUPER+grave in modules/home/hyprland/config.nix.

set -eu

CONFIG_DIR="$HOME/dotfiles/nixos/.config/nixos"

# Resolve the claude binary to an absolute path. Hyprland's exec environment
# may not include the npm bin dir on PATH, so fall back to the install path.
CLAUDE="$(command -v claude 2>/dev/null || echo "$HOME/.npm-packages/bin/claude")"
if [ ! -x "$CLAUDE" ]; then
  notify-send -u critical -i dialog-error "system-fix" "claude binary not found at $CLAUDE"
  exit 1
fi

# Briefing appended to Claude's system prompt. CLAUDE.md (repo + global) is
# still read automatically; this just frames the session as a fix workflow.
BRIEFING="$(cat <<'EOF'
You were launched from a Hyprland hotkey (SUPER+grave) as Matt's "system fix"
assistant for this repo: his NixOS + Home Manager + Hyprland dotfiles. He will
describe a bug, an annoyance, or a feature he wants added to his system.

How to work:
- If the request is ambiguous, ask 1-2 sharp clarifying questions first.
- Find the relevant module: modules/core/* for system-level config,
  modules/home/* for user / Home-Manager config, modules/home/scripts for scripts.
- Make minimal, idiomatic changes. Format Nix with alejandra.
- The active host is `laptop`. Validate with `nix flake check`, and run
  `nixos-rebuild test --flake .#laptop` when a change warrants it.
- Finish by summarizing what changed and how to apply it (the `rebuild` alias).
EOF
)"

exec kitty \
  --title system-fix \
  --directory "$CONFIG_DIR" \
  -e "$CLAUDE" --dangerously-skip-permissions --append-system-prompt "$BRIEFING"
