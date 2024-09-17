{
  description = "Matt's nixos configuration (based off FrostPhoenix)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nur.url = "github:nix-community/NUR";

    hypr-contrib.url = "github:hyprwm/contrib";
    hyprpicker.url = "github:hyprwm/hyprpicker";

    alejandra.url = "github:kamadorueda/alejandra/3.0.0";

    nix-gaming.url = "github:fufexan/nix-gaming";

    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      submodules = true;
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin-bat = {
      url = "github:catppuccin/bat";
      flake = false;
    };
    catppuccin-cava = {
      url = "github:catppuccin/cava";
      flake = false;
    };
    catppuccin-starship = {
      url = "github:catppuccin/starship";
      flake = false;
    };

    spicetify-nix.url = "github:gerg-l/spicetify-nix";
    spicetify-nix.inputs.nixpkgs.follows = "nixpkgs";
    zen-browser.url = "github:MarceColl/zen-browser-flake";
  };

  outputs = {
    nixpkgs,
    self,
    home-manager,
    ...
  } @ inputs: let
    username = "matth";
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    lib = nixpkgs.lib;

    sharedVariables = import ./shared-variables.nix;
  in {
    nixosConfigurations = {
      desktop = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [(import ./hosts/desktop)];
        specialArgs = {
          host = "desktop";
          inherit self inputs username sharedVariables;
        };
      };
      laptop = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [(import ./hosts/laptop)];
        specialArgs = {
          host = "laptop";
          inherit self inputs username sharedVariables;
        };
      };
      vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [(import ./hosts/vm)];
        specialArgs = {
          host = "vm";
          inherit self inputs username sharedVariables;
        };
      };
    };
    #   homeConfigurations = {
    #     "matth@laptop" = home-manager.lib.homeManagerConfiguration {
    #       pkgs = pkgs;
    #       extraSpecialArgs = {inherit inputs self;};
    #
    #       modules = [
    #         ./modules/home/default.nix
    #         {
    #           home = {
    #             username = "matth";
    #             homeDirectory = "/home/matth";
    #             stateVersion = "24.05"; # Use the appropriate version
    #           };
    #         }
    #       ];
    #     };
    #     # Add similar configurations for desktop and vm if needed
    #   };
  };
}
