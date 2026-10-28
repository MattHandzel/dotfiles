# Ignore list for the `claude` Syncthing folder (~/.claude), shared between the
# Mac and matts-server, installed identically on every host that shares it.
#
# Until 2026-10-28 this was a home.file symlink into the nix store. Syncthing
# does not follow a symlinked .stignore, so the list never applied, and had the
# folder been paired it would have synced everything, credentials included. Now
# a real file, the same way obsidian-vault-stignore.nix installs the vault's.
# The list itself is modules/home/claude.stignore (a whitelist; see its header).
{
  lib,
  pkgs,
  ...
}: {
  home.activation.claudeStignore = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -d "$HOME/.claude" ]; then
      run rm -f "$HOME/.claude/.stignore"
      run install -m 644 ${./claude.stignore} "$HOME/.claude/.stignore"
    fi
  '';
}
