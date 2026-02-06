{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./../../modules/core/server.nix
  ];

  services.ollama = {
    enable = true;
    acceleration = "cuda";
    openFirewall = true;
    host = "0.0.0.0";
  };

  services.atuin.enable = true;
  networking.hostName = "matts-server";

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  environment.systemPackages = with pkgs; [
    cargo
    rustup
    brightnessctl # Maybe useful for debugging, harmless
    powertop
    cudaPackages.cuda_nvcc
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    cudaPackages.cutensor
    gcc12

    # Server Dev Tools
    tailscale
    mosh
    tmux
    git
    ripgrep
    fd
    fzf
    bat
    zoxide
    btop
    direnv
    just
    restic
  ];

    services = {
      syncthing = {
        enable = true;
        user = "matth";
        dataDir = "/home/matth";
        configDir = "/home/matth/.config/syncthing";
        guiAddress = "127.0.0.1:8384";
        openDefaultPorts = false;
      };
    };
  
    systemd.timers."website-update" = {
      description = "Timer to update the website project";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 00,20:00:00";
        Persistent = true;
      };
    };
  
    systemd.services."website-update" = {      description = "Update and push website project";
      serviceConfig = {
        User = "matth";
        Group = "users";
        Type = "oneshot";
        WorkingDirectory = "/home/matth/Projects/website";
      };
      script = with pkgs; ''
        export HOME=/home/matth
        export GIT_AUTHOR_NAME="Matt's Server"
        export GIT_AUTHOR_EMAIL="handzelmatthew@gmail.com"
        export GIT_COMMITTER_NAME="Matt's Server"
        export GIT_COMMITTER_EMAIL="handzelmatthew@gmail.com"

        git pull
        bash ./reset.sh
        git commit -am "Updating website at $(date)"
        git push --no-verify
      '';
    };

  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "performance";

  home-manager.backupFileExtension = "backup_$(date +%Y-%m-%d_%H-%M-%S)";

  services.openssh.enable = true;
  services.tailscale.enable = true;

  networking.firewall.interfaces.tailscale0.allowedUDPPortRanges = [
    { from = 60000; to = 61000; }
  ];

  hardware.nvidia-container-toolkit.enable = true;
  hardware.graphics.enable32Bit = true;
}