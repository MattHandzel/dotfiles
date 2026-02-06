{
  inputs,
  username,
  host,
  ...
}: {
  imports = [
    (import ./bat.nix)
    (import ./btop.nix)
    (import ./git.nix)
    (import ./nvim.nix)
    (import ./packages-server.nix)
    (import ./starship.nix)
    (import ./tmux.nix)
    (import ./zsh.nix)
    (import ./services.nix) # Check if these services are GUI-dependent
    inputs.catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    flavor = "mocha";
    enable = true;
  };

  home.sessionVariables = {
    EDITOR = "nvim";
  };
}
