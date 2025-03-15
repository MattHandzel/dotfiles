(self: super: {
  hyprsession = super.pkgs.rustPlatform.buildRustPackage {
    pname = "hyprsession";
    version = "0.1.3";
    src = super.fetchFromGitHub {
      owner = "joshurtree";
      repo = "hyprsession";
      rev = "main";
      sha256 = "sha256-3Ach9qcpM426enzSNQ0xjYlkeWlgh2nExwy9pUGiFws="; # Replace with actual hash
    };
    cargoSRI = "sha256-1mDV/+8Q3+NSOdRha3fPSzrSFNDo0IvdbiuIsuaD+x4="; # Replace with actual hash
    cargoHash = "sha256-1mDV/+8Q3+NSOdRha3fPSzrSFNDo0IvdbiuIsuaD+x4="; # Replace with actual hash

    nativeBuildInputs = with super.pkgs; [pkg-config];
    buildInputs = with super.pkgs; [hyprland];
  };
})
