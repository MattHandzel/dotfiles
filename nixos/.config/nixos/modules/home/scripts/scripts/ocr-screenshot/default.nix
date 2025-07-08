{pkgs ? import <nixpkgs> {}}: let
  pythonEnv = pkgs.python312.withPackages (ps:
    with ps; [
      pillow
      pytesseract
    ]);
in
  pkgs.stdenv.mkDerivation {
    name = "ocr-screenshot";
    src = ./.;

    buildInputs = [
      pythonEnv
      pkgs.tesseract
      pkgs.grim
      pkgs.slurp
      pkgs.wl-clipboard
    ];

    installPhase = ''
      mkdir -p $out/bin
      cp ocr-screenshot.py $out/bin/ocr-screenshot
      chmod +x $out/bin/ocr-screenshot
    '';
  }
