#!/usr/bin/env bash
# Re-applies the copilot-cmp deprecation fix after lazy clones or updates the
# plugin (lazy checks out upstream, discarding local edits, then runs `build` --
# so this must be idempotent and must FAIL LOUDLY, never silently, or the
# warning spam returns).
#
# Upstream calls `self.client.is_stopped()` with a dot; on Neovim 0.11+ that
# field is a deprecation shim, so is_available() -- which runs on nearly every
# completion request -- warned constantly. See the patch header for detail.
#
# lazy.nvim runs `build` with cwd set to the plugin directory.
set -euo pipefail

PATCH="$HOME/dotfiles/nvim/.config/nvim/patches/copilot-cmp-is-stopped-deprecation.patch"

if [[ ! -f "$PATCH" ]]; then
  echo "copilot-cmp is_stopped patch: MISSING at $PATCH -- deprecation spam will return" >&2
  exit 1
fi

if patch -p1 --dry-run --reverse --force <"$PATCH" >/dev/null 2>&1; then
  echo "copilot-cmp is_stopped patch: already applied"
  exit 0
fi

patch -p1 --forward <"$PATCH"
echo "copilot-cmp is_stopped patch: applied"
