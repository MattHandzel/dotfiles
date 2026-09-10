#!/usr/bin/env bash
# Re-applies the obsidian.nvim invalid-alias warning fix after lazy clones or
# updates the plugin (lazy checks out upstream, discarding local edits, then
# runs `build` -- so this must be idempotent and must FAIL LOUDLY, never
# silently, or the bug returns invisibly as "N error(s) occurred during search"
# with a stack trace and zero usable results).
#
# Upstream bug: lua/obsidian/note.lua concatenates `path` (an obsidian.Path
# TABLE) into the "Invalid alias value" warning. Raising the warning therefore
# raises a Lua error, which escapes Note.from_file_async and aborts the entire
# search -- one malformed note takes down every result. See the header of the
# patch file for the full explanation.
#
# lazy.nvim runs `build` with cwd set to the plugin directory.
set -euo pipefail

PATCH="$HOME/dotfiles/nvim/.config/nvim/patches/obsidian-alias-warn-path.patch"

if [[ ! -f "$PATCH" ]]; then
  echo "obsidian alias patch: MISSING at $PATCH -- a bad alias will still abort search" >&2
  exit 1
fi

if patch -p1 --dry-run --reverse --force <"$PATCH" >/dev/null 2>&1; then
  echo "obsidian alias-warning patch: already applied"
  exit 0
fi

patch -p1 --forward <"$PATCH"
echo "obsidian alias-warning patch: applied"
