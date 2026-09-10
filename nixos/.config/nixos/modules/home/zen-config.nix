{
  config,
  lib,
  pkgs,
  ...
}: let
  managedPrefs = import ./lib/zen-managed-prefs.nix {inherit pkgs;};
in {
  # On every home-manager rebuild, refresh the nix-managed block in each
  # Zen profile's user.js. Existing user-authored prefs outside our markers
  # are preserved. Profiles without a prefs.js (i.e., never run) are skipped.
  home.activation.zenTabUnloading = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PATH="${pkgs.coreutils}/bin:${pkgs.gawk}/bin:$PATH"
    for prof in "$HOME"/.zen/*/; do
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
