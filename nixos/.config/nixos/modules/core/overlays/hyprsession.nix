(self: super: {
  hyprsession = super.pkgs.rustPlatform.buildRustPackage rec {
    pname = "hyprsession";
    version = "0.1.0";
    src = super.fetchFromGitHub {
      owner = "joshurtree";
      repo = "hyprsession";
      rev = "main";
      sha256 = "sha256-3Ach9qcpM426enzSNQ0xjYlkeWlgh2nExwy9pUGiFws="; # Replace with actual hash
    };
    cargoSha256 = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="; # Replace with actual hash
    nativeBuildInputs = with super.pkgs; [pkg-config];
    buildInputs = with super.pkgs; [hyprland];
  };
})
