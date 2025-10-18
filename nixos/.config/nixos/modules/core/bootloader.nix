{pkgs, ...}: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.kernelParams = ["usbcore.autosuspend=-1" "mem_sleep_default=s2idle" "button.lid_init_state=open"];
  # "usbcore.autosuspend=-1"
  # "mem_sleep_default=s2idle"  # Changed from "deep"
  # "button.lid_init_state=open"
  # "loglevel=4"
  # "lsm=landlock,yama,bpf"
  # "acpi_sleep=nonvs"

  boot.kernelModules = ["uvcvideo" "video"];
}
