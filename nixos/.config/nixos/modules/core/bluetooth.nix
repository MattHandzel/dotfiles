{pkgs, ...}: {
  services.blueman = {
    enable = true;
  };

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Auto-connect trusted devices on boot/resume. NOTE: do NOT set
  # `Experimental = true` here — it enables BlueZ LE Audio, which makes the
  # EarFun buds connect over LE (no A2DP transport ⇒ no PipeWire sink ⇒
  # "connected but silent"). Keeping it off forces classic A2DP.
  hardware.bluetooth.settings = {
    General = {
      FastConnectable = true;
      JustWorksRepairing = "always";
    };
    Policy = {
      AutoEnable = true;
    };
  };

  # adding headset button controls
  systemd.user.services.mpris-proxy = {
    description = "Mpris proxy";
    after = ["network.target" "sound.target"];
    wantedBy = ["default.target"];
    serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
  };

  # systemd.user.services.my-user-task = {
  #   enable = true;
  #   description = "My daily task notification";
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "notify-send -t 2000 -u normal -i dialog-information \"Daily task 📅!\" \"\"";
  #   };
  #   wantedBy = ["default.target"];
  # };

  systemd.user.timers.my-user-task = {
    enable = true;
    description = "Run my daily task";
    timerConfig = {
      OnCalendar = "13:47";
      Unit = "my-user-task.service";
    };
    wantedBy = ["timers.target"];
  };
}
