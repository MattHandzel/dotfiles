{
  pkgs,
  config,
  lib,
  inputs,
  ...
}: let
  sharedVariables = import ../../shared_variables.nix;
in {
  # Rebuilds and a heavy Electron app load (Beeper/Discord/Slack/Zen/Claude)
  # have repeatedly driven this 16 GB laptop into swap thrash that presents as
  # "apps stop receiving input" — load avg >10 dominated by D-state IO wait,
  # /proc/pressure/io showing ~35% full stall.
  # Root cause measured 2026-06-25: at 55% the zram tier ran 99% full while
  # ~3.4 GB spilled onto the disk swapfile; with swappiness=100 the kernel then
  # paged that anon to disk continuously — that disk paging is the stall.
  # zstd compresses ~4x here (6.4 GB of data held in 1.7 GB of real RAM), so a
  # 100% disksize (~15 GB nominal) costs only ~3.8 GB RAM even when full and
  # keeps the whole working set in compressed RAM, demoting the disk swapfile
  # to a true emergency last resort. systemd-oomd remains the OOM backstop.
  # mkForce overrides modules/core/system.nix which sets these too.
  zramSwap = {
    enable = lib.mkForce true;
    algorithm = lib.mkForce "zstd";
    memoryPercent = lib.mkForce 100;
    priority = lib.mkForce 100;
  };

  # Enable systemd-oomd for better memory pressure handling.
  systemd.oomd = {
    enable = true;
    enableUserSlices = true;
    enableSystemSlice = true;
    enableRootSlice = true;
  };

  # KSM (Kernel Same-page Merging) deduplicates identical anonymous pages
  # across processes. With many Electron apps running (Discord, Slack, Beeper,
  # Cursor, VSCode, Brave) the V8/Chromium runtime pages overlap heavily —
  # realistic savings are 200–500 MB anon at modest CPU cost.
  hardware.ksm.enable = true;

  # Move /tmp off tmpfs (RAM-backed) onto the disk-backed root filesystem.
  # Memwatch observed 1.6 GB sitting in /tmp tmpfs — that's RAM the working
  # set could use. cleanOnBoot preserves the per-boot-clean behavior.
  boot.tmp = {
    useTmpfs = false;
    cleanOnBoot = true;
  };

  # Override modules/core/system.nix's vm.swappiness=5. With zram absorbing
  # anonymous pages cheaply, a high swappiness lets the kernel evict cold
  # anon to compressed RAM rather than holding it and starving file cache.
  boot.kernel.sysctl."vm.swappiness" = lib.mkForce 100;

  # Anti-stutter tuning for the zram swap tier:
  # - page-cluster=0: zram is RAM-speed random access, so the default swap-in
  #   read-ahead (8 pages) just wastes work and adds latency. 0 = fault in one
  #   page at a time, which is the recommended setting for zram.
  # - watermark_scale_factor=125: make kswapd start reclaiming earlier and keep
  #   more free-page headroom (~1.25% of RAM). This avoids allocations hitting
  #   synchronous *direct reclaim*, which is what makes the UI sputter/freeze
  #   under a sudden memory spike. Default is 10.
  boot.kernel.sysctl."vm.page-cluster" = lib.mkForce 0;
  boot.kernel.sysctl."vm.watermark_scale_factor" = lib.mkForce 125;

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }
  ];

  # ── Headset-mic combo-jack quirk for ALC245 + SOF on Lunar Lake ──
  # Acer Swift SF16-51T's BIOS ships pin-config 0x411111f0 (= "unused") for
  # every codec input pin, so the kernel HDA driver doesn't expose a Headset
  # Mic capture path even though the chassis has a 3.5mm combo jack.
  # The dell-headset-multi quirk retasks the input pins via the legacy
  # `snd-hda-intel` codec quirk path. SOF still drives the bus; the codec
  # quirk applies to the Realtek codec module that SOF delegates to.
  # Empirically tested on related ALC22x/23x/25x/26x/27x/28x/29x systems.
  # Engine: 2026-05-10 — see projects/stt-tune/follow-ups/jack-mic-modprobe.md
  boot.extraModprobeConfig = ''
    options snd-hda-intel model=dell-headset-multi
  '';

  # netdata removed globally in modules/core/services.nix

  # Fix: Restart NetworkManager after suspend to resolve wifi flakiness
  environment.etc."systemd/system-sleep/99-wifi-recover" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # Args: $1 = pre|post, $2 = suspend|hibernate|hybrid-sleep
      case "$1" in
        post)
          # Wait a moment for hardware to wake up
          sleep 2
          # Restart NetworkManager to re-initialize connections
          /run/current-system/sw/bin/systemctl restart NetworkManager.service
          ;;
      esac
    '';
  };

  # Fix: espanso stops expanding after suspend. It reads keystrokes straight
  # from /dev/input (EVDEV) on Wayland and enumerates the keyboards ONCE at
  # startup — it never re-scans. It's bound to hyprland-session.target, which
  # fires once at login and not on resume, so after every suspend the worker
  # keeps running but its capture is stale and silently dead until restarted.
  # On this laptop that's ~12 suspends/day, which is why "most of the time it
  # doesn't work." Restart the user service on resume so a fresh worker
  # re-grabs the input devices every wake. Runs as root from the sleep hook,
  # so reach matth's user manager over the machined bus.
  environment.etc."systemd/system-sleep/98-espanso-recover" = {
    mode = "0755";
    text = ''
      #!/bin/sh
      # Args: $1 = pre|post, $2 = suspend|hibernate|hybrid-sleep
      case "$1" in
        post)
          # Let the input devices and user bus settle before re-grabbing.
          sleep 2
          /run/current-system/sw/bin/systemctl --machine=matth@.host --user \
            restart espanso.service || true
          ;;
      esac
    '';
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
  nixpkgs.overlays = [inputs.claude-desktop.overlays.default];
  imports = [
    ./hardware-configuration.nix
    ./../../modules/core
    ./../../modules/core/gmail-automation.nix
    ./../../modules/core/focus-failopen-watchdog.nix
    ./../../modules/core/focus-state-agent.nix
    ./../../modules/core/kanata-homerow.nix
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
    claude-desktop-fhs
    (pkgs.callPackage ../../pkgs/mermaid-editor/default.nix {})
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
      # This is a Lunar Lake CPU on intel_pstate in *active* mode, which only
      # exposes the `powersave` and `performance` governors (no schedutil).
      # On intel_pstate, `powersave` is already a dynamic governor that scales
      # to turbo — responsiveness is actually controlled by the energy
      # performance preference (EPP), not the governor name. The default on
      # battery was `balance_power`, which ramps clocks lazily and made the UI
      # feel sluggish unplugged. `balance_performance` ramps eagerly while
      # still saving power at idle.
      battery = {
        governor = "powersave";
        energy_performance_preference = "balance_performance";
      };
      charger = {
        governor = "performance";
        energy_performance_preference = "performance";
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

  # Must be a STATIC suffix: Home Manager appends it literally as a filename
  # extension, so a `$(date …)` substitution here never expands and instead
  # produces a malformed backup path that makes the activation `mv` fail
  # (silently leaving colliding files unmanaged). Plain string only.
  home-manager.backupFileExtension = "hm-backup";

  services.fprintd.enable = true;
}
