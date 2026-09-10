#!/usr/bin/env bash
# Re-applies the ghost-text.nvim first-document race fix after lazy clones or
# updates the plugin (lazy checks out upstream, discarding local edits, then
# runs `build` -- so this must be idempotent and must FAIL LOUDLY, never
# silently, or the bug returns invisibly as "GhostText connects and nothing
# happens").
#
# Upstream bug: app/server/websocket.ts `message` returned early while the async
# `open` handler was still creating the buffer. The browser sends its document
# once, immediately on connect, and never resends -- so that first document was
# dropped and the buffer stayed empty.
#
# lazy.nvim runs `build` with cwd set to the plugin directory.
set -euo pipefail

PATCH="$HOME/dotfiles/nvim/.config/nvim/patches/ghost-text-buffer-race.patch"

if [[ ! -f "$PATCH" ]]; then
  echo "ghost-text patch: MISSING at $PATCH -- first-document race is UNFIXED" >&2
  exit 1
fi

if patch -p1 --dry-run --reverse --force <"$PATCH" >/dev/null 2>&1; then
  echo "ghost-text race patch: already applied"
  exit 0
fi

patch -p1 --forward <"$PATCH"
echo "ghost-text race patch: applied"
