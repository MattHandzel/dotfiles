{ pkgs, ... }:
{  
  hardware = {
    graphics = {
      enable = true;
      extraPackages = with pkgs; [

      ];
    };
    uinput.enable = true;
  };
  hardware.enableRedistributableFirmware = true;
}
