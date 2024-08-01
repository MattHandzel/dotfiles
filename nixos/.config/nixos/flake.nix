{
# Nixos flake
description = "Home mannager configuration";

inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  nix-colors.url = "github:misterio77/nix-colors";


};

outputs = { self, nixpkgs, ... }@inputs:
let
  system = "x86_64-linux";
  pkgs = import nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
    };
  };
in
{
  nixosConfigurations = {
    main = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs system; };

      modules = [
        ./configuration.nix
      ];



    };
  };
};
}
