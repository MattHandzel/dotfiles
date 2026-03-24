{
  pkgs,
  inputs,
  username,
  host,
  self,
  ...
}: {
  imports = [inputs.home-manager.nixosModules.home-manager];
  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    extraSpecialArgs = {inherit inputs username host self;};
    users.${username} = {
      imports =
        if (host == "desktop")
        then [./../home/default.desktop.nix]
        else if (host == "server")
        then [./../home/server.nix]
        else [./../home];
      home.username = "${username}";
      home.homeDirectory = "/home/${username}";
      home.stateVersion = "25.11";
      programs.home-manager.enable = true;
      xdg.desktopEntries.foliate = {
        name = "Foliate";
        exec = "env GDK_BACKEND=x11 foliate %U";
        icon = "com.github.johnfactotum.Foliate";
        categories = ["Office"];
      };
      xdg.desktopEntries.planify = {
        name = "Planify";
        exec = "env GDK_BACKEND=x11 planify %U";
        icon = "io.github.alainm23.planify";
        categories = ["Office" "X-Productivity"];
      };
    };
  };

  users.users.${username} = {
    isNormalUser = true;
    description = "${username}";
    extraGroups = ["networkmanager" "wheel" "adbusers" "docker" "dialout" "video" "render" "input" "uinput" "i2c"];
    shell = pkgs.zsh;
  };
  nix.settings.allowed-users = ["${username}"];

  # Run nixos rebuild without sudo
  security.sudo.wheelNeedsPassword = false;

  services.tailscale.enable = true;
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [22];
  services.openssh = {
    enable = true;
    ports = [22];
    settings = {
      PasswordAuthentication = true;
      AllowUsers = null;
      PermitRootLogin = "yes";
    };
  };
}
