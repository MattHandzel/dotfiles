# Everything that would otherwise be a click in System Settings.
#
# These are the macOS equivalents of what modules/core/system.nix + the Hyprland
# config do on Linux: keyboard repeat fast enough to be usable with vim motions,
# no text "assistance" that rewrites what you typed, no animations in the way of
# a keyboard-driven window manager, and a Finder that shows the truth.
{
  pkgs,
  username,
  ...
}: {
  system.keyboard = {
    enableKeyMapping = true;
    # Caps is Escape (kanata and Karabiner do the rest — see modules/darwin/kanata.nix
    # and modules/home/darwin/karabiner.nix). This one is the firmware-level
    # remap that survives even before kanata loads at boot.
    remapCapsLockToEscape = true;
  };

  system.startup.chime = false;

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;

      # 1 / 10 are the fastest values the sliders can reach. Anything slower
      # makes held-down hjkl unusable.
      KeyRepeat = 1;
      InitialKeyRepeat = 10;
      # Press-and-hold shows the accent picker instead of repeating the key —
      # the single worst default for a vim user.
      ApplePressAndHoldEnabled = false;

      # Every form of "helpful" text rewriting, off. Smart quotes in particular
      # silently corrupt code and shell snippets pasted between apps.
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticInlinePredictionEnabled = false;

      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      PMPrintingExpandedStateForPrint = true;
      PMPrintingExpandedStateForPrint2 = true;
      NSDocumentSaveNewDocumentsToCloud = false;

      # Window resize animation is pure latency under a tiling WM.
      NSWindowResizeTime = 0.001;
      NSWindowShouldDragOnGesture = true;

      "com.apple.swipescrolldirection" = true; # natural scrolling ON
      "com.apple.keyboard.fnState" = true; # F-keys are F-keys; kanata owns layers
      "com.apple.mouse.tapBehavior" = 1; # tap to click
      "com.apple.sound.beep.feedback" = 0;
    };

    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
      TrackpadRightClick = true;
      ActuationStrength = 0; # silent click
    };

    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.15;
      show-recents = false;
      static-only = true;
      mru-spaces = false; # AeroSpace assigns workspaces; do not reorder them
      launchanim = false;
      expose-animation-duration = 0.1;
      tilesize = 36;
      orientation = "left"; # out of the way, like waybar
      minimize-to-application = true;
      # Every hot corner off — 1 is "no action". An accidental corner throw in
      # the middle of a drag is exactly the kind of surprise this setup avoids.
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;
    };

    finder = {
      AppleShowAllFiles = true;
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv"; # list view
      FXDefaultSearchScope = "SCcf"; # search the current folder, not the Mac
      QuitMenuItem = true;
      CreateDesktop = false; # no icons on the desktop
    };

    screencapture = {
      location = "/Users/${username}/Pictures/Screenshots";
      type = "png";
      disable-shadow = true;
    };

    # AeroSpace wants ONE space spanning both displays; with this off, moving a
    # window between monitors changes space and the workspace bindings desync.
    spaces.spans-displays = true;

    WindowManager = {
      GloballyEnabled = false; # Stage Manager off
      EnableStandardClickToShowDesktop = false;
      StandardHideDesktopIcons = true;
    };

    menuExtraClock = {
      Show24Hour = true;
      ShowSeconds = true;
      ShowDayOfWeek = true;
    };

    controlcenter.BatteryShowPercentage = true;
    loginwindow.GuestEnabled = false;
    LaunchServices.LSQuarantine = false;
    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;

    # Firewall on with stealth mode (Phase 8 security defaults).
    alf = {
      globalstate = 1;
      stealthenabled = 1;
    };

    CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
      # 64 = Cmd+Space (Spotlight). Disabled so Raycast can take the slot.
      # macOS only re-reads this at login, so the first switch needs a logout
      # (or one manual toggle in System Settings) before it takes effect.
      "64".enabled = false;
    };
  };

  # Touch ID instead of typing the password for every sudo. This is the macOS
  # analogue of `security.sudo.wheelNeedsPassword = false` on the NixOS hosts,
  # without actually removing the authentication.
  security.pam.services.sudo_local.touchIdAuth = true;

  fonts.packages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.inter
  ];

  # screencapture.location above is only honoured if the directory exists.
  system.activationScripts.screenshotsDir.text = ''
    mkdir -p "/Users/${username}/Pictures/Screenshots"
    chown ${username} "/Users/${username}/Pictures/Screenshots" || true
  '';
}
