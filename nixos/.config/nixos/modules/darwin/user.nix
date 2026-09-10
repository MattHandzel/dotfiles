# Home Manager wiring for the Mac — the mirror of modules/core/user.nix.
#
# Home Manager is a SUBMODULE here (not a standalone `home-manager switch`),
# exactly as on NixOS, which is what makes `osConfig` available to home modules
# — several of them read sops secret paths out of it.
{
  inputs,
  username,
  host,
  self,
  pkgs,
  ...
}: {
  # home-manager-darwin, NOT home-manager: the Mac's pkgs come from
  # nixpkgs-darwin, and home-manager has to be from the same era as the nixpkgs
  # it is paired with. See the input comment in flake.nix.
  imports = [inputs.home-manager-darwin.darwinModules.home-manager];

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
    shell = pkgs.zsh;
  };

  # nix-darwin needs zsh enabled at the system level for the /etc/zshrc it
  # installs (the one that puts the nix profile on PATH for login shells).
  programs.zsh.enable = true;

  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    extraSpecialArgs = {inherit inputs username host self;};
    backupFileExtension = "hm-backup";
    users.${username} = {
      imports = [./../home];
      home.username = username;
      home.homeDirectory = "/Users/${username}";
      home.stateVersion = "25.11";
      programs.home-manager.enable = true;
    };
  };
}
