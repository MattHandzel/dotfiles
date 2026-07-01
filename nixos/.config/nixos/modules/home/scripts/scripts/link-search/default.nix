{pkgs ? import <nixpkgs> {}}:
# link-search: fuzzy-search links across clipboard history (cliphist) + browser
# history (Zen places.sqlite). Bound to Super+Shift+V. See link-search.py.
pkgs.stdenv.mkDerivation {
  name = "link-search";
  src = ./.;

  nativeBuildInputs = [pkgs.makeWrapper];

  # python3 ships sqlite3 in stdlib; the rest are called by name at runtime.
  runtimeDeps = [
    pkgs.python3
    pkgs.cliphist
    pkgs.fuzzel
    pkgs.wl-clipboard # wl-copy
    pkgs.libnotify # notify-send
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp link-search.py $out/bin/.link-search-unwrapped
    chmod +x $out/bin/.link-search-unwrapped
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/link-search \
      --add-flags "$out/bin/.link-search-unwrapped" \
      --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.cliphist pkgs.fuzzel pkgs.wl-clipboard pkgs.libnotify]}
  '';
}
