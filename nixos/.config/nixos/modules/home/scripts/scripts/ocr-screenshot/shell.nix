{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  buildInputs = [
    pkgs.python312 # or the version of Python you're using
    pkgs.python312Packages.pip
    pkgs.python312Packages.setuptools
    # pkgs.python311Packages.pytesseract
    # pkgs.python311Packages.pillow
    pkgs.tesseract # Tesseract OCR
    pkgs.grim # grim (for grimblast)
    pkgs.slurp # slurp (dependency for grimblast)
    pkgs.wl-clipboard # wl-copy (dependency for grimblast)
  ];

  shellHook = ''
  '';
}
