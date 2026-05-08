{
  self,
  pkgs,
  lib,
  inputs,
  ...
}: {
  #imports = [ inputs.nix-gaming.nixosModules.default ];
  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = ["nix-command" "flakes"];
      # Limit build parallelism to prevent OOM during CUDA compilation
      max-jobs = 2;
      cores = 4;
      substituters = [
        "https://nix-gaming.cachix.org"
        "https://cuda-maintainers.cachix.org"
      ];
      trusted-public-keys = [
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 90d";
    };
  };
  nixpkgs = {
    overlays = [
      inputs.nur.overlays.default
      (import ./overlays/command-not-found.nix)
      # (import ./overlays/hyprsession.nix)
    ];
  };

  environment.systemPackages = with pkgs; [
    wget
    git
  ];

  time.timeZone = "America/Los_Angeles";
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  i18n.inputMethod = {
    enable = true;
    type = "ibus";
    ibus.engines = with pkgs.ibus-engines; [
      /*
      any engine you want, for example
      */
      anthy
    ];
  };

  # Create /bin/bash for FHS compatibility — third-party tools (e.g. Claude
  # Code plugins) hardcode #!/bin/bash shebangs and break without it.
  system.activationScripts.bash-compat = {
    text = ''ln -sf "${pkgs.bash}/bin/bash" /bin/bash'';
    deps = [ "etc" ];
  };

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.05";
}
