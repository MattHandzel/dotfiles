# Ignore list for the Obsidian vault Syncthing folder (r9mpp-yvvmy, ~/Obsidian),
# installed identically on every host that has the vault.
#
# It used to be hand-edited per machine and the copies drifted: on 2026-10-25
# the Mac's had editor/build patterns the server's lacked, and neither ignored
# Main/.claude/worktrees (14 GB of agent checkouts) or the per-OS venvs. The
# vault was also not syncing at all then (see syncthing.md), so the drift only
# showed when the two were paired again.
#
# A real file, not a store symlink: Syncthing won't follow a symlinked .stignore.
{
  lib,
  pkgs,
  ...
}: {
  home.activation.obsidianVaultStignore = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -d "$HOME/Obsidian" ]; then
      run rm -f "$HOME/Obsidian/.stignore"
      run install -m 644 ${./obsidian-vault.stignore} "$HOME/Obsidian/.stignore"
    fi
  '';
}
