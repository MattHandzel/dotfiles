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

      # Mic fix (2026-07-14): this laptop's SOF audio exposes TWO internal capture
      # nodes — "Digital Microphone" (Mic1, the real working DMIC) and "Stereo
      # Microphone" (Mic2, the analog combo-jack input, dead-silent when nothing is
      # plugged in). WirePlumber kept auto-selecting Mic2 as the default when a USB
      # (Jabra) / Bluetooth headset disconnected, so every app recorded pure
      # silence. Drop Mic2's session priority far below Mic1 so the working digital
      # mic is always the internal fallback. Headsets are untouched (their own
      # priorities are unchanged) and Mic2 can still be picked manually if a real
      # analog headset mic is plugged in.
      extraConfig."51-mic-priority" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {
                "node.name" = "alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Mic2__source";
              }
            ];
            actions.update-props."priority.session" = 100;
          }
        ];
      };
    };
  };
  environment.systemPackages = with pkgs; [
    # pulseaudioFull
    pipewire
  ];
}
