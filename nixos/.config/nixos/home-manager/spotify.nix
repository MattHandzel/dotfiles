{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  spicePkgs = inputs.spicetify-nix.packages.${pkgs.system}.default;
in {
 nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["spotify"];
  imports = [
    inputs.spicetify-nix.homeManagerModules.default];

programs.spicetify =
  let
     spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
   in
   {
     enable = true;
     enabledExtensions = with spicePkgs.extensions; [
       adblock
       hidePodcasts
       shuffle
      keyboardShortcut
      shuffle
      playlistIntersection
      skipStats
     ];
     theme = spicePkgs.themes.catppuccin;
     colorScheme = "mocha";
   };
}
