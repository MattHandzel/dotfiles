{
  pkgs,
  config,
  ...
}: let
  sharedVariables = import ../../shared_variables.nix;
in {
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "electron-28.3.3"
    "electron-32.3.3"
    "electron-30.5.1"
  ];
  imports = [
    ./hardware-configuration.nix
    ./../../modules/core
  ];

  environment.systemPackages = with pkgs; [
    hyprsession
    acpi
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
        governor = "power";
        turbo = "never";
      };
      charger = {
        governor = "performance";
        turbo = "auto";
      };
    };

    syncthing = {
      enable = true;
      user = "matth";
      dataDir = "/home/matth/.config/syncthing/";
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
    #     ExecStart = "${sharedVariables.rootDirectory}/modules/home/scripts/scripts/suspend-script-runner.sh pre";
    #   };
    # };
    #
    # "custom-pre-hibernate" = {
    #   before = ["systemd-hibernate.service"];
    #   wantedBy = ["systemd-hibernate.service"];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     Environment = "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/sbin:/usr/sbin";
    #     ExecStart = "${sharedVariables.rootDirectory}/modules/home/scripts/scripts/suspend-script-runner.sh pre";
    #   };
    # };

    # "custom-post-resume" = {
    #   wantedBy = ["post-resume.target"];
    #   # conflicts = ["shutdown.target" "reboot.target" "suspend.target" "hibernate.target"];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     Environment = "PATH=/run/current-system/sw/bin:/bin:/usr/bin:/sbin:/usr/sbin:/etc/profiles/per-user/matth/bin/";
    #     ExecStart = "${sharedVariables.rootDirectory}/modules/home/scripts/scripts/suspend-script-runner.sh post";
    #   };
    # };
  };

  services.udev.packages = [
    pkgs.platformio-core
    pkgs.openocd
  ];

  services.udev.extraRules = ''
    "ACTION=="add", SUBSYSTEM=="pci", DRIVER=="pcieport", ATTR{power/wakeup}="disabled"
  '';

  services.tlp = {
    enable = false;
    settings = {
      # CPU_SCALING_GOVERNOR_ON_AC = "performance";
      # CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      #
      # CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      # CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      #
      # CPU_MIN_PERF_ON_AC = 0;
      # CPU_MAX_PERF_ON_AC = 100;
      # CPU_MIN_PERF_ON_BAT = 0;
      # CPU_MAX_PERF_ON_BAT = 20;
      #
      #Optional helps save long term battery health
      START_CHARGE_THRESH_BAT0 = 40; # 40 and bellow it starts to charge
      STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging

      USB_AUTOSUSPEND = 0;
      RESTORE_DEVICE_STATE_ON_STARTUP = 1;
    };
  };

  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "performance";

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
