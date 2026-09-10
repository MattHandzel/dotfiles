#!/usr/bin/env bash
# Re-applies the obsidian.nvim NakedUrl trailing-`=` fix after lazy clones or
# updates the plugin (lazy checks out upstream, discarding local edits, then
# runs `build` -- so this must be idempotent and must FAIL LOUDLY, never
# silently, or the bug returns invisibly as "[Obsidian.nvim] Failed to resolve
# file 'https://...=='" whenever following a base64-padded URL).
#
# Upstream bug: search.lua's NakedUrl pattern requires the URL's last char to
# be [a-zA-Z0-9/], so URLs ending in `=` (base64 ids, e.g. Swapcard profile
# links) fail is_url() and follow-link treats them as unresolvable notes. See
# the header of the patch file for the full explanation.
#
# lazy.nvim runs `build` with cwd set to the plugin directory.
set -euo pipefail

PATCH="$HOME/dotfiles/nvim/.config/nvim/patches/obsidian-naked-url-trailing-equals.patch"

if [[ ! -f "$PATCH" ]]; then
  echo "obsidian naked-url patch: MISSING at $PATCH -- URLs ending in '=' will fail to open" >&2
  exit 1
fi

if patch -p1 --dry-run --reverse --force <"$PATCH" >/dev/null 2>&1; then
  echo "obsidian naked-url patch: already applied"
  exit 0
fi

patch -p1 --forward <"$PATCH"
echo "obsidian naked-url patch: applied"
