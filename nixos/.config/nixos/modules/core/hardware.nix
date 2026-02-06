{pkgs, ...}: {
  hardware = {
    enableRedistributableFirmware = true;
    graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-compute-runtime
        intel-media-driver
      ];
    };
    uinput.enable = true;
  };
}
