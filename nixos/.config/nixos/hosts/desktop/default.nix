{
  pkgs,
  config,
  ...
}: let
  sharedVariables = import ../../shared_variables.nix;
in {
  # Also make sure to enable cuda support in nixpkgs, otherwise transcription will
  # be painfully slow. But be prepared to let your computer build packages for 2-3 hours.
  nixpkgs.config.cudaSupport = true;
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    # "electron-28.3.3"
    # "electron-32.3.3"
    # "electron-30.5.1"
  ];
  imports = [
    ./hardware-configuration.nix
    ./../../modules/core
  ];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    openFirewall = true;
    host = "0.0.0.0";
  };
  networking.hostName = "matts-server"; # Define your hostname.

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  environment.systemPackages = with pkgs; [
    # hyprsession
    cargo
    rustup
    # ucpi
    brightnessctl
    powertop
    cudaPackages.cuda_nvcc
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    cudaPackages.libcutensor
    gcc
  ];

  services = {
    hardware = {
      openrgb.enable = true;
    };
    syncthing = {
      enable = true;
      user = "matth";
      dataDir = "/home/matth/.config/syncthing/";
    };
    # docker = {
    #   enable = true;
    #   enableNvidia = true;
    # };

    # logkeys = {
    #   description = "Logkeys keylogger";
    #   wantedBy = ["default.target"];
    #   serviceConfig = {
    #     ExecStart = "${pkgs.logkeys}/bin/logkeys --start --output=$HOME/notes/life-logging/key-logging/keylog.log --device=/dev/input/eventX";
    #     Restart = "always";
    #     RestartSec = "10";
    #   };
    # };
  };

  systemd.services = {
    # "custom-pre-suspend" = {
    #   before = ["systemd-suspend.service"];
    #   wantedBy = ["systemd-suspend.service"];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     Environment = "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/sbin:/usr/sbin";
    #     ExecStart = "${self}/modules/home/scripts/scripts/suspend-script-runner.sh pre";
    #   };
    # };
    #
    # "custom-pre-hibernate" = {
    #   before = ["systemd-hibernate.service"];
    #   wantedBy = ["systemd-hibernate.service"];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     Environment = "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/sbin:/usr/sbin";
    #     ExecStart = "${self}/modules/home/scripts/scripts/suspend-script-runner.sh pre";
    #   };
    # };

    # "custom-post-resume" = {
    #   wantedBy = ["post-resume.target"];
    #   # conflicts = ["shutdown.target" "reboot.target" "suspend.target" "hibernate.target"];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     Environment = "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/sbin:/usr/sbin:/etc/profiles/per-user/matth/bin/";
    #     ExecStart = "${self}/modules/home/scripts/scripts/suspend-script-runner.sh post";
    #   };
    # };
    "website-update" = {
      description = "Update and push website project";
      serviceConfig = {
        # Running the job as the user "matth".
        User = "matth";
        Group = "users";
        Type = "oneshot";
        # Setting the working directory.
        WorkingDirectory = "/home/matth/Projects/website";
      };
      # This defines the script that will be executed.
      script = with pkgs; ''
        # This makes sure git can find the right credentials
        export HOME=/home/matth
        export GIT_AUTHOR_NAME="Matt's Server"
        export GIT_AUTHOR_EMAIL="handzelmatthew@gmail.com"
        export GIT_COMMITTER_NAME="Matt's Server"
        export GIT_COMMITTER_EMAIL="handzelmatthew@gmail.com"

        # The command sequence to run
        git pull
        bash ./reset.sh
        # Using the standard shell command for the current date in the commit message
        git commit -am "Updating website at $(date)"
        git push --no-verify
      '';
    };
  };

  systemd.timers."website-update" = {
    description = "Timer to update the website project";
    wantedBy = ["timers.target"];
    timerConfig = {
      # Runs at 8 PM (20:00) and midnight (00:00) every day.
      OnCalendar = "*-*-* 00,20:00:00";
      # If a run is missed (e.g., PC was off), it will run on the next boot.
      Persistent = true;
    };
  };

  services.udev.packages = [
    pkgs.platformio-core
    pkgs.openocd
  ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", DRIVER=="pcieport", ATTR{power/wakeup}="disabled"
    # Allow i2c group to access i2c devices (for ddccontrol etc)
    KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
  '';

  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "performance";

  # boot = {
  #   kernelModules = ["acpi_call"];
  #   extraModulePackages = with config.boot.kernelPackages;
  #     [
  #       acpi_call
  #       cpupower
  #     ]
  #     ++ [pkgs.cpupower-gui];
  # };

  # services.printing.enable = true;
  # services.printing.drivers = [ pkgs.printer-drivers ];

  home-manager.backupFileExtension = "backup_$(date +%Y-%m-%d_%H-%M-%S)";

  services.fprintd.enable = true;
  services.openssh.enable = true;

  # docker has access to gpu
  hardware.nvidia-container-toolkit.enable = true;
  hardware.graphics.enable32Bit = true;
}
