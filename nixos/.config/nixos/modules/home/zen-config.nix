{
  config,
  lib,
  pkgs,
  ...
}: let
  managedPrefs = pkgs.writeText "zen-managed-prefs.js" ''
    // === BEGIN nix-managed === (from modules/home/zen-config.nix)
    // DO NOT EDIT — rewritten on every home-manager rebuild.
    // To customize, edit modules/home/zen-config.nix and rebuild.

    // Aggressively unload background tabs when memory is tight.
    user_pref("browser.tabs.unloadOnLowMemory", true);

    // On startup, do not eagerly restore tabs — wait for click.
    user_pref("browser.sessionstore.restore_on_demand", true);

    // A tab must be inactive at least this long before it is eligible for
    // unload (2 minutes; default 10 min). Lowered from 5min (2026-07) so the
    // low-memory unloader can reclaim cold tabs sooner — Zen is the single
    // largest memory pool (~2.6GB) on this 16GB machine.
    user_pref("browser.tabs.min_inactive_duration_before_unload", 120000);

    // Halve the number of content processes (default 8). Slightly slower
    // cross-origin tab switches; meaningfully less memory.
    user_pref("dom.ipc.processCount", 4);

    // Cap in-memory cache (default is auto, often >256 MB).
    user_pref("browser.cache.memory.capacity", 65536);

    // Scale the entire UI 25% larger (1.0 = default).
    user_pref("layout.css.devPixelsPerPx", "1.25");
    // === END nix-managed ===
  '';
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
