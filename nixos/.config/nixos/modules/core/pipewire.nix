{pkgs, ...}: {
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true; # core
    alsa.enable = true; # for audio
    pulse.enable = true; # if you still want PulseAudio clients
    wireplumber = {
      enable = true; # for session management
    };
  };
  environment.systemPackages = with pkgs; [
    # pulseaudioFull
    pipewire
  ];
}
