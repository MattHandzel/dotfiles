{pkgs, ...}: {
  hardware.pulseaudio.enable = false;
  services.pipewire = {
    enable = true; # core
    alsa.enable = true; # for audio
    pulse.enable = true; # if you still want PulseAudio clients
    wireplumber = {
      enable = true; # for session management
      # Bluetooth headphone reliability: force classic A2DP (omitting the LE-Audio
      # bap roles avoids the half-negotiation that leaves buds "connected" with no
      # PipeWire sink), enable high-quality codecs + hardware volume.
      extraConfig."10-bluez" = {
        "monitor.bluez.properties" = {
          "bluez5.enable-sbc-xq" = true;
          "bluez5.enable-msbc" = true;
          "bluez5.enable-hw-volume" = true;
          "bluez5.roles" = ["a2dp_sink" "a2dp_source" "hfp_hf" "hfp_ag"];
        };
      };
    };
  };
  environment.systemPackages = with pkgs; [
    # pulseaudioFull
    pipewire
  ];
}
