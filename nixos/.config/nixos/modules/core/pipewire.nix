{ pkgs, ... }: 
{
  hardware.pulseaudio.enable = true;
  services.pipewire = {
    enable = false;
    # alsa.enable = true;
    # alsa.support32Bit = true;
    # pulse.enable = true;
    # # lowLatency.enable = true;
  };
  environment.systemPackages = with pkgs; [
    pulseaudioFull
  ];
}
