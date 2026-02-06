{
  pkgs,
  config,
  lib,
  ...
}: let
  sharedVariables = import ../../shared_variables.nix;
in {
  # Rebuilds on this laptop have previously driven the system into swap
  # exhaustion and OOM thrash (appearing as a hard freeze). zram gives us a
  # fast, compressed swap tier and reduces IO pressure.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  nix.settings = {
    auto-optimise-store = true;
    # Keep rebuilds from saturating a thermally-constrained laptop.
    # You can temporarily override on the CLI with `--option max-jobs ...`.
    #
    # With zram enabled, we can afford moderate parallelism without falling
    # into the swap/OOM spiral that previously looked like "freezes".
    max-jobs = lib.mkDefault 2;
    cores = lib.mkDefault 6;
  };
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

  environment.systemPackages = with pkgs; [
    # hyprsession
    cargo
    rustup
    # ucpi
    brightnessctl
    powertop
    fprintd
    pam
  ];

  services = {
    thermald.enable = true;
    # cpupower-gui.enable = true;
    power-profiles-daemon.enable = false;

    upower = {
      enable = true;
      percentageLow = 20;
      percentageCritical = 5;
      percentageAction = 3;
      criticalPowerAction = "Hibernate";
    };

    auto-cpufreq.enable = true;
    auto-cpufreq.settings = {
      battery = {
        governor = "powersave";
      };
      charger = {
        governor = "performance";
      };
    };

    syncthing = {
      enable = true;
      user = "matth";
      dataDir = "/home/matth/.config/syncthing";
      configDir = "/home/matth/.config/syncthing";
    };

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
  powerManagement.resumeCommands = ''
  '';

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

  services.tlp = {
    enable = true;
    settings = {
      # auto-cpufreq is enabled, so we disable TLP's CPU management to avoid conflicts
      CPU_SCALING_GOVERNOR_ON_AC = lib.mkForce "";
      CPU_SCALING_GOVERNOR_ON_BAT = lib.mkForce "";
      CPU_ENERGY_PERF_POLICY_ON_AC = lib.mkForce "";
      CPU_ENERGY_PERF_POLICY_ON_BAT = lib.mkForce "";

      #Optional helps save long term battery health
      START_CHARGE_THRESH_BAT0 = 60; # 60 and bellow it starts to charge
      STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging

      USB_AUTOSUSPEND = 0;
      RESTORE_DEVICE_STATE_ON_STARTUP = 1;
    };
  };

  powerManagement.enable = false; # auto-cpufreq handles scaling policies

  boot = {
    kernelModules = ["acpi_call"];
    extraModulePackages = with config.boot.kernelPackages;
      [
        acpi_call
        cpupower
      ]
      ++ [pkgs.cpupower-gui];
  };

  # services.printing.enable = true;
  # services.printing.drivers = [ pkgs.printer-drivers ];

  home-manager.backupFileExtension = "backup_$(date +%Y-%m-%d_%H-%M-%S)";

  services.fprintd.enable = true;
}
