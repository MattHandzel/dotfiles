{
  pkgs,
  inputs,
  username,
  host,
  ...
}: {
  imports = [inputs.home-manager.nixosModules.home-manager];
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    extraSpecialArgs = {inherit inputs username host;};
    users.${username} = {
      imports =
        if (host == "desktop")
        then [./../home/default.desktop.nix]
        else if (host == "server")
        then [./../home/server.nix]
        else [./../home];
      home.username = "${username}";
      home.homeDirectory = "/home/${username}";
      home.stateVersion = "25.05";
      programs.home-manager.enable = true;
    };
  };

  users.users.${username} = {
    isNormalUser = true;
    description = "${username}";
    extraGroups = ["networkmanager" "wheel" "adbusers" "docker" "dialout" "video" "render" "input"];
    shell = pkgs.zsh;
  };
  nix.settings.allowed-users = ["${username}"];

  # Run nixos rebuild without sudo
  security.sudo.wheelNeedsPassword = false; # This allows users in the 'wheel' group to run any command with sudo without a password.
}
