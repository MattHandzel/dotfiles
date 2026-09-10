{
  pkgs,
  username,
  ...
}: {
  environment.systemPackages = with pkgs; [
    libinput
  ];
  services = {
    xserver = {
      enable = true;
      xkb.layout = "us";
      xkb.options = "fn:fnmode,caps:swapescape";
      exportConfiguration = true;
    };

    displayManager.autoLogin = {
      enable = true;
      user = "${username}";
    };
    libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
        tapping = true;
        scrollMethod = "twofinger";
        middleEmulation = true;
        disableWhileTyping = true;
      };
      # keyboard = {
      #   options = "fk:2";
      #
      #         };
      # tapping = true;
      # naturalScrolling = false;
      # mouse = {
      #   accelProfile = "flat";
      # };
    };
  };
  # disable-while-typing (dwt) only suppresses the touchpad for keyboards
  # libinput has tagged AttrKeyboardIntegration=internal — see tp_want_dwt()
  # in evdev-mt-touchpad.c, which returns false for anything else. kanata's
  # virtual keyboard already qualifies (it reports bus ps2, so libinput's
  # 10-generic-keyboard.quirks "[Serial Keyboards]" rule tags it internal),
  # which is why the built-in keyboard suppresses the touchpad.
  #
  # The TOTEM does not: kbd-relay (modules/home/kbd-relay.nix) re-emits it as
  # a USB-bus virtual device "Keyboard Relay" with no quirk at all, and the
  # TOTEM's own Bluetooth node is tagged *external* by libinput. Result: with
  # the TOTEM resting over the palm rest, typing on it left the touchpad fully
  # live. Tag both as internal so dwt pairs them with the touchpad.
  #
  # Verify after a rebuild with:
  #   libinput debug-events --verbose | rg 'dwt activated'
  # — expect one line per keyboard, including Keyboard Relay.
  environment.etc."libinput/local-overrides.quirks".text = ''
    [Local kbd-relay virtual keyboard]
    MatchName=Keyboard Relay
    AttrKeyboardIntegration=internal

    [Local TOTEM keyboard]
    MatchName=*TOTEM Keyboard
    AttrKeyboardIntegration=internal
  '';

  # To prevent getting stuck at shutdown
  systemd.settings.Manager = {
    DefaultTimeoutStopSec = "10s";
  };
}
