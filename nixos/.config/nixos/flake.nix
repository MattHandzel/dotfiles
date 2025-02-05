{
  description = "Matt's nixos configuration (based off FrostPhoenix)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-24.11-darwin";

    nur.url = "github:nix-community/NUR";

    hypr-contrib.url = "github:hyprwm/contrib";
    hyprpicker.url = "github:hyprwm/hyprpicker";

    alejandra.url = "github:kamadorueda/alejandra/3.0.0";

    nix-gaming.url = "github:fufexan/nix-gaming";
    notion-repackaged = {
      url = "github:MattHandzel/nix-notion-repackaged/master";

      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      type = "git";
      url = "https://github.com/hyprwm/Hyprland";
      submodules = true;
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin-bat = {
      url = "github:catppuccin/bat";
      flake = false;
    };
    catppuccin-cava = {
      url = "github:catppuccin/cava/6ec25ba688e30f3e5d6004ef6a295e6ba90c64d4";
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

    sharedVariables = import ./shared-variables.nix;
  in {
    # nixpkgs = {
    #   overlay = final: prev: {
    #     nixpkgs.config.permittedInsecurePackages = [
    #       "electron-28.3.3"
    #       "electron-30.5.1"
    #     ];
    #   };
    # };

    # packages.x86_64-linux = notion-repackaged.packages.${system}.default;

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
        modules = [
          (import ./hosts/laptop)
        ];
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
