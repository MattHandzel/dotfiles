{
  inputs,
  pkgs,
  ...
}: {
  imports =
    [(import ./hyprland.nix)]
    ++ [(import ./config.nix)]
    ++ [(import ./displays.nix)]
    ++ [(import ./hyprlock.nix)]
    ++ [(import ./hyprsession.nix)]
    ++ [(import ./variables.nix)];
  # ++ [inputs.hyprland.homeManagerModules.default];
  # ++ [inputs.hyprsession.packages.${pkgs.system}.hyprsession];
}
