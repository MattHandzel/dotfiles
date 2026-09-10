{pkgs ? import <nixpkgs> {}}:
# link-search: fuzzy-search links across clipboard history (cliphist) + browser
# history (Zen places.sqlite). Bound to Super+Shift+V. See link-search.py.
# On macOS the picker is choose (via the fuzzel shim) and the clipboard is
# pbcopy/pbpaste; only tesseract-free stdlib Python is needed there.
let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  runtimeDeps =
    (pkgs.lib.optionals isLinux [pkgs.cliphist pkgs.fuzzel pkgs.wl-clipboard pkgs.libnotify])
    ++ pkgs.lib.optionals (!isLinux) [pkgs.choose-gui pkgs.terminal-notifier];
in
  pkgs.stdenv.mkDerivation {
    name = "link-search";
    src = ./.;

    nativeBuildInputs = [pkgs.makeWrapper];

    installPhase = ''
      mkdir -p $out/bin
      cp link-search.py $out/bin/.link-search-unwrapped
      chmod +x $out/bin/.link-search-unwrapped
      makeWrapper ${pkgs.python3}/bin/python3 $out/bin/link-search \
        --add-flags "$out/bin/.link-search-unwrapped" \
        --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps}
    '';
  }
