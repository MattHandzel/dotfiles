# ocr-screenshot: pick a screen region, OCR it with tesseract, copy the text.
# Stdlib-only Python: grimblast (Linux) or screencapture (macOS) takes the
# picture, the tesseract CLI reads it, wl-copy / pbcopy receives the text.
{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs.stdenv.hostPlatform) isLinux;
in
  pkgs.stdenv.mkDerivation {
    name = "ocr-screenshot";
    src = ./.;

    nativeBuildInputs = [pkgs.makeWrapper];

    installPhase = ''
      mkdir -p $out/bin
      cp ocr-screenshot.py $out/bin/.ocr-screenshot-unwrapped
      chmod +x $out/bin/.ocr-screenshot-unwrapped
      makeWrapper ${pkgs.python3}/bin/python3 $out/bin/ocr-screenshot \
        --add-flags "$out/bin/.ocr-screenshot-unwrapped" \
        --prefix PATH : ${pkgs.lib.makeBinPath ([pkgs.tesseract] ++ pkgs.lib.optionals isLinux [pkgs.grim pkgs.slurp pkgs.wl-clipboard])}
    '';
  }
