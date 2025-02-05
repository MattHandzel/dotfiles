{pkgs, ...}: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.kernelPackages = pkgs.linuxPackages_6_12;

  boot.kernelParams = ["usbcore.autosuspend=-1" "mem_sleep_default=deep" "button.lid_init_state=open" "acpi_sleep=nonvs"];
}
