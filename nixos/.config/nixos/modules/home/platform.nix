# Installs the six cross-platform desktop primitives (see lib/platform-scripts.nix)
# on every host, so a script can say `clip-copy` / `notify` / `open-it` and mean
# the same thing on Hyprland and on macOS.
{pkgs, ...}: {
  home.packages = builtins.attrValues (import ./lib/platform-scripts.nix {inherit pkgs;});
}
