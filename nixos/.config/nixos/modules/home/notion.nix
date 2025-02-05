# {
#   pkgs,
#   lib,
#   inputs,
#   ...
# }: let
#   spicePkgs = inputs.notion-enchanced.legacyPackages.${pkgs.system};
# in {
#   # nixpkgs.config.allowUnfreePredicate = pkg:
#   #   builtins.elem (lib.getName pkg) [
#   #     "spotify"
#   #   ];
#   # pkgs.en = [
#     # inputs.notion-repackaged.packages.x86_64-linux.notion-repackaged
#   # ];
#
#   # imports = [inputs.spicetify-nix.homeManagerModules.default];
#   # programs.notion = {
#   #   enable = true;
#   #   theme = spicePkgs.themes.catppuccin;
#   #   colorScheme = "mocha";
#   # };
#
#   # programs.spicetify = {
#   #   enable = true;
#   #   enabledExtensions = with spicePkgs.extensions; [
#   #     adblock
#   #     hidePodcasts
#   #     shuffle # shuffle+ (special characters are sanitized out of extension names)
#   #   ];
#   #   theme = spicePkgs.themes.catppuccin;
#   #   colorScheme = "mocha";
#   # };
# }
