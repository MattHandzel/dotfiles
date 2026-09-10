#!/usr/bin/env bash
# Re-applies the obsidian.nvim visual-line column fix after lazy clones or
# updates the plugin (lazy checks out upstream, discarding local edits, then
# runs `build` -- so this must be idempotent and must FAIL LOUDLY, never
# silently, or the bug returns invisibly as "Invalid 'end_col': out of range"
# from ObsidianExtractNote with a stack trace, an orphan note, and the
# selected text still sitting in the source file.
#
# Upstream bug: lua/obsidian/util.lua hardcodes `cscol, cecol = 0, 999` for a
# live visual-LINE selection. Those columns go straight into
# nvim_buf_set_text, where 999 is out of range on any line under 999 bytes.
# See the header of the patch file for the full explanation.
#
# lazy.nvim runs `build` with cwd set to the plugin directory.
set -euo pipefail

PATCH="$HOME/dotfiles/nvim/.config/nvim/patches/obsidian-visual-line-columns.patch"

if [[ ! -f "$PATCH" ]]; then
  echo "obsidian visual-line patch: MISSING at $PATCH -- ObsidianExtractNote will crash on V selections" >&2
  exit 1
fi

if patch -p1 --dry-run --reverse --force <"$PATCH" >/dev/null 2>&1; then
  echo "obsidian visual-line patch: already applied"
  exit 0
fi

patch -p1 --forward <"$PATCH"
echo "obsidian visual-line patch: applied"
