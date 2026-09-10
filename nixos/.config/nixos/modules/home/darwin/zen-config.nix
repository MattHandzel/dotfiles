# Zen Browser prefs on macOS. Identical managed block to the Linux module
# (modules/home/lib/zen-managed-prefs.nix); only the profile root differs —
# Zen keeps profiles in ~/Library/Application Support/zen/Profiles here rather
# than ~/.zen.
{
  lib,
  pkgs,
  ...
}: let
  managedPrefs = import ../lib/zen-managed-prefs.nix {inherit pkgs;};
in {
  home.activation.zenTabUnloading = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PATH="${pkgs.coreutils}/bin:${pkgs.gawk}/bin:$PATH"
    for prof in "$HOME/Library/Application Support/zen/Profiles"/*/; do
      [ -f "$prof/prefs.js" ] || continue
      user_js="$prof/user.js"
      tmp=$(mktemp)
      if [ -f "$user_js" ]; then
        awk '
          /^\/\/ === BEGIN nix-managed ===/ { skip=1 }
          !skip { print }
          /^\/\/ === END nix-managed ===/   { skip=0 }
        ' "$user_js" > "$tmp"
      fi
      cat ${managedPrefs} >> "$tmp"
      mv "$tmp" "$user_js"
    done
  '';
}
