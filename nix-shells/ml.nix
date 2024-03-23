let
  pkgs = import <nixpkgs> {};
in pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (python-pkgs: [
      python-pkgs.pandas
      python-pkgs.requests
      python-pkgs.torch
      python-pkgs.matplotlib
      python-pkgs.pillow
      python-pkgs.torchvision
      python-pkgs.scikit-image
      python-pkgs.scipy
      python-pkgs.numpy


    ]))
  ];

shellHook = ''
  ~/dotfiles/nix-shells/default-shell-hooks.sh
  '';
}
