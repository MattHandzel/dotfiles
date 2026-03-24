{
  self,
  pkgs,
  lib,
  inputs,
  ...
}: let
  sharedVariables = import ../../shared_variables.nix;
in {
  #imports = [ inputs.nix-gaming.nixosModules.default ];
  nix = {
    settings = {
      auto-optimise-store = true;
      experimental-features = ["nix-command" "flakes"];
      substituters = ["https://nix-gaming.cachix.org"];
      trusted-public-keys = ["nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="];
    };

    gc = {
      automatic = true;
      dates = "weekly"; # Or "daily", "monthly", etc.
      options = "--delete-older-than 14d +3"; # Keeps 14 days of generations
    };
  };
  nixpkgs = {
    overlays = [
      inputs.nur.overlays.default
      (import ./overlays/command-not-found.nix)
      # (import ./overlays/hyprsession.nix)
    ];
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 40; # Use up to 40% of RAM for zRAM
    priority = 100;
  };
  boot.kernel.sysctl = {
    # Lower swappiness to reduce proactive swapping of app working sets.
    # We still keep zram available for memory spikes.
    "vm.swappiness" = 5;
  };

  environment.systemPackages = with pkgs; [
    wget
    git
    lm_sensors
    nvme-cli
    wsdd
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
  system.stateVersion = "25.11";

  environment.variables.SERVER_IP_ADDRESS = sharedVariables.serverIpAddress;
}
