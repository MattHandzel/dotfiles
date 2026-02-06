{pkgs, ...}: {
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true; # core
    alsa.enable = true; # for audio
    pulse.enable = true; # if you still want PulseAudio clients
    wireplumber = {
      enable = true; # for session management
      extraConfig."51-default-source.conf" = {
        "monitor.alsa.rules" = [
          {
            matches = [
              {"node.name" = "alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Mic2__source";}
            ];
            actions.update-props = {
              "priority.session" = 2000;
              "node.default" = true;
              "node.description" = "Built-in Digital Microphone";
            };
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
