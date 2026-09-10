# Everything that would otherwise be a click in System Settings.
#
# These are the macOS equivalents of what modules/core/system.nix + the Hyprland
# config do on Linux: keyboard repeat fast enough to be usable with vim motions,
# no text "assistance" that rewrites what you typed, no animations in the way of
# a keyboard-driven window manager, and a Finder that shows the truth.
#
# 2026-09-10: every `defaults write` from ~/migration/mac-personalize.sh and
# ~/migration/mac-tune.sh that Matt applied live is expressed here — through the
# nix-darwin option when one exists, otherwise through CustomUserPreferences
# (same key, same domain, same value as the script). What is NOT here, and why:
#   - pmset / mdutil / nvram / systemsetup lines: not `defaults`, and nix-darwin
#     has no option that writes the same thing (system.startup.chime covers the
#     StartupMute nvram key; power.sleep.* cannot express -c 10 vs -b 5).
#   - `defaults -currentHost` (ByHost) writes: nix-darwin has no ByHost support;
#     every one of them has a non-host twin above that is set.
#   - com.apple.universalaccess reduceMotion: `defaults read` shows it never
#     took (the write needs Full Disk Access for the calling terminal), and a
#     rebuild from a terminal without FDA would fail on it. Left out on purpose.
#   - Finder sidebar (a Swift tool), wallpaper, duti default apps, kitty.conf,
#     bordersrc: not defaults keys; kitty and borders are owned by
#     modules/home/{kitty,darwin/aerospace}.nix.
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

      # SketchyBar is THE bar (modules/home/darwin/sketchybar.nix); the macOS
      # menu bar stays hidden. macOS writes this as _HIHideMenuBar; the
      # _HideMenuBar twin the tune script also set is in CustomUserPreferences.
      _HIHideMenuBar = true;

      # 1 / 10 are the fastest values the sliders can reach. Anything slower
      # makes held-down hjkl unusable.
      KeyRepeat = 1;
      InitialKeyRepeat = 10;
      # Press-and-hold shows the accent picker instead of repeating the key —
      # the single worst default for a vim user.
      ApplePressAndHoldEnabled = false;
      # Full keyboard access: Tab reaches every control in every dialog.
      AppleKeyboardUIMode = 2;

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
      NSDocumentSaveNewDocumentsToCloud = false; # save to disk, not iCloud

      # Window animations are pure latency under a tiling WM.
      NSAutomaticWindowAnimationsEnabled = false;
      NSWindowResizeTime = 0.001;
      NSWindowShouldDragOnGesture = true; # ctrl+cmd drag anywhere (Hyprland habit)

      # Look: small sidebar icons, no wallpaper tinting, scrollbars only while
      # scrolling. Accent/highlight colour (Purple) is in CustomUserPreferences.
      NSTableViewDefaultSizeMode = 1;
      AppleReduceDesktopTinting = true;
      AppleShowScrollBars = "WhenScrolling";
      AppleICUForce24HourTime = true;

      "com.apple.swipescrolldirection" = true; # natural scrolling ON
      "com.apple.keyboard.fnState" = true; # F-keys are F-keys; kanata owns layers
      "com.apple.mouse.tapBehavior" = 1; # tap to click
      "com.apple.trackpad.scaling" = 2.5;
      "com.apple.trackpad.enableSecondaryClick" = true;
      "com.apple.trackpad.forceClick" = true;
      "com.apple.sound.beep.feedback" = 0; # no volume-change feedback beep
    };

    trackpad = {
      Clicking = true;
      TrackpadThreeFingerDrag = true;
      TrackpadRightClick = true; # two-finger secondary click …
      TrackpadCornerSecondaryClick = 0; # … not a corner click
      FirstClickThreshold = 0; # light click
      SecondClickThreshold = 0;
      ActuationStrength = 0; # silent click
    };

    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.15;
      show-recents = false;
      static-only = true;
      mru-spaces = false; # AeroSpace assigns workspaces; do not reorder them
      expose-group-apps = false; # Mission Control does not group by app
      launchanim = false;
      expose-animation-duration = 0.1;
      magnification = false;
      tilesize = 36;
      orientation = "left"; # out of the way, like waybar
      minimize-to-application = true;
      show-process-indicators = true;
      # Pinned apps: exactly these, in this order (the dockutil list from
      # mac-personalize.sh). Downloads stack gone; Trash stays.
      persistent-apps = [
        "/Applications/kitty.app"
        "/Applications/Zen.app"
        "/Applications/Obsidian.app"
        "/Applications/Slack.app"
        "/Applications/Beeper Desktop.app"
        "/Applications/Superhuman.app"
        "/Applications/Bitwarden.app"
      ];
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
      _FXSortFoldersFirst = true;
      FXEnableExtensionChangeWarning = false;
      FXPreferredViewStyle = "Nlsv"; # list view
      FXDefaultSearchScope = "SCcf"; # search the current folder, not the Mac
      # PfHm. nix-darwin only allows NewWindowTargetPath together with "Other",
      # but the live pair is PfHm + the home URL, so the path is set in
      # CustomUserPreferences below.
      NewWindowTarget = "Home";
      QuitMenuItem = true;
      CreateDesktop = false; # no icons on the desktop
      ShowExternalHardDrivesOnDesktop = false;
      ShowRemovableMediaOnDesktop = false;
    };

    screencapture = {
      location = "/Users/${username}/Pictures/Screenshots";
      type = "png";
      disable-shadow = true;
      show-thumbnail = false; # no floating preview to wait out
    };

    # AeroSpace wants ONE space spanning both displays; with this off, moving a
    # window between monitors changes space and the workspace bindings desync.
    spaces.spans-displays = true;

    WindowManager = {
      GloballyEnabled = false; # Stage Manager off
      EnableStandardClickToShowDesktop = false;
      StandardHideDesktopIcons = true;
    };

    # Day + time only ("EEE HH:mm", the DateFormat is in CustomUserPreferences),
    # no date, no seconds flashing.
    menuExtraClock = {
      Show24Hour = true;
      ShowSeconds = true;
      ShowDayOfWeek = true;
      ShowDate = 2; # never
      FlashDateSeparators = false;
      IsAnalog = false;
    };

    # The controlcenter.* options write `Sound = 24`-style keys; the live
    # machine uses the "NSStatusItem Visible <item>" keys instead (below), so
    # only the option whose key matches is used here.
    controlcenter.BatteryShowPercentage = true;

    loginwindow = {
      GuestEnabled = false;
      SHOWFULLNAME = true; # name + password fields, not user icons
      LoginwindowText = "Matt Handzel · handzelmatthew@gmail.com";
    };
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };
    # Globe/Fn key does nothing on its own; kanata owns the layers.
    hitoolbox.AppleFnUsageType = "Do Nothing";
    LaunchServices.LSQuarantine = false;
    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;

    CustomUserPreferences = {
      NSGlobalDomain = {
        _HideMenuBar = true; # the tune script's spelling; _HIHideMenuBar above is the real key
        NSQuitAlwaysKeepsWindows = false; # do not resurrect windows on login
        AppleAccentColor = 5; # Purple — the closest system accent to Mauve
        AppleHighlightColor = "0.968627 0.831373 1.000000 Purple";
        AppleFnUsageType = 0; # same as hitoolbox.AppleFnUsageType, NSGlobalDomain copy
        "com.apple.sound.uiaudio.enabled" = 0; # UI sound effects off
        "com.apple.sound.beep.flash" = 0;
        # The nix-darwin option only accepts 1; the live value is 0 (no corner click).
        "com.apple.trackpad.trackpadCornerClickBehavior" = 0;
      };

      "com.apple.dock".no-bouncing = true; # no Dock icon bounce for attention

      "com.apple.finder" = {
        DisableAllAnimations = true;
        WarnOnEmptyTrash = false;
        NewWindowTargetPath = "file:///Users/${username}/"; # see finder.NewWindowTarget
      };
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = true; # no .DS_Store litter on shares …
        DSDontWriteUSBStores = true; # … or USB sticks
      };

      "com.apple.menuextra.clock".DateFormat = "EEE HH:mm";

      # Menu-bar items: only battery, Wi-Fi and the clock; everything else is
      # SketchyBar's job (and Ice hides the rest).
      "com.apple.controlcenter" = {
        "NSStatusItem Visible Battery" = true;
        "NSStatusItem Visible WiFi" = true;
        "NSStatusItem Visible Clock" = true;
        "NSStatusItem Visible Siri" = false;
        "NSStatusItem Visible Spotlight" = false;
        "NSStatusItem Visible Bluetooth" = false;
        "NSStatusItem Visible Sound" = false;
        "NSStatusItem Visible Display" = false;
        "NSStatusItem Visible NowPlaying" = false;
        "NSStatusItem Visible ScreenMirroring" = false;
        "NSStatusItem Visible AirDrop" = false;
        "NSStatusItem Visible FocusModes" = false;
        "NSStatusItem Visible KeyboardBrightness" = false;
        "NSStatusItem Visible UserSwitcher" = false;
        "NSStatusItem Visible Hearing" = false;
        "NSStatusItem Visible AccessibilityShortcuts" = false;
        "NSStatusItem Visible MusicRecognition" = false;
      };

      # Siri, suggestions, Game Center, notification previews: the "noise"
      # section of mac-personalize.sh.
      "com.apple.Siri" = {
        StatusMenuVisible = false;
        VoiceTriggerUserEnabled = false;
        SiriPrefStashedStatusMenuVisible = false;
      };
      "com.apple.assistant.support"."Assistant Enabled" = false;
      "com.apple.assistant.backedup"."Cloud Sync Enabled" = false;
      "com.apple.lookup.shared".LookupSuggestionsDisabled = true; # Siri suggestions in Look Up
      "com.apple.suggestions".SuggestionsAppLibraryEnabled = false;
      "com.apple.gamed".Disabled = true; # Game Center
      "com.apple.ncprefs".content_visibility = 2; # notification previews only when unlocked
      "com.apple.Photos".AnalysisEnabled = false; # no background photo analysis

      # 64 = Cmd+Space (Spotlight), 65 = Cmd+Option+Space (Finder search
      # window). Both disabled so Raycast can take Cmd+Space. macOS only
      # re-reads this at login, so the first switch needs a logout (or one
      # manual toggle in System Settings) before it takes effect.
      "com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
        "64".enabled = false;
        "65".enabled = false;
      };

      # ── third-party apps whose prefs the personalize script set ──
      "com.raycast.macos" = {
        raycastGlobalHotkey = "Command-49"; # Cmd+Space
        raycastShouldFollowSystemAppearance = true;
        onboardingCompleted = true;
        "NSStatusItem Visible raycastIcon" = false;
      };
      "com.apphousekitchen.aldente-pro" = {
        chargeVal = 80; # the tlp 60/80 threshold, upper half
        showDockIcon = false;
        launchOnLogin = true;
      };
      # Stats: CPU / RAM / battery only, mini widgets in Purple.
      "eu.exelban.Stats" = {
        setupProcess = true;
        telemetry = false;
        runAtLoginInitialized = true;
        "update-interval" = "Never";
        CPU_state = true;
        RAM_state = true;
        Battery_state = true;
        Disk_state = false;
        Network_state = false;
        GPU_state = false;
        Sensors_state = false;
        Bluetooth_state = false;
        Clock_state = false;
        CPU_widget = "mini";
        CPU_mini_color = "Purple";
        RAM_widget = "mini";
        RAM_mini_color = "Purple";
        Battery_widget = "battery";
        Battery_battery_percentage = true;
      };
      # Ice: click the icon to reveal hidden menu-bar items, re-hide on its own.
      "com.jordanbaird.Ice" = {
        ShowIceIcon = true;
        ShowOnHover = false;
        ShowOnClick = true;
        ShowOnScroll = false;
        AutoRehide = true;
        RehideStrategy = 0;
        IceBarLocation = 0;
        UseIceBar = false;
        HideApplicationMenus = false;
        EnableAlwaysHiddenSection = false;
      };
      # Terminal.app falls back to Basic if the catppuccin-mocha profile has
      # not been imported yet (`open ~/migration/catppuccin-mocha.terminal`).
      "com.apple.Terminal" = {
        "Default Window Settings" = "catppuccin-mocha";
        "Startup Window Settings" = "catppuccin-mocha";
      };
    };
  };

  # Firewall on with stealth mode (Phase 8 security defaults). `system.defaults.alf`
  # was removed from nix-darwin and is now a hard assertion failure, not a warning.
  # globalstate = 1 meant "on, allowing signed and explicitly permitted services",
  # which is `enable` without `blockAllIncoming`; stealthenabled = 1 is
  # `enableStealthMode`. Same as mac-tune.sh's two socketfilterfw lines.
  networking.applicationFirewall = {
    enable = true;
    blockAllIncoming = false;
    enableStealthMode = true;
  };

  # Touch ID instead of typing the password for every sudo. This is the macOS
  # analogue of `security.sudo.wheelNeedsPassword = false` on the NixOS hosts,
  # without actually removing the authentication. `reattach` loads
  # pam_reattach first so the Touch ID prompt also appears inside tmux.
  #
  # The overnight lane forced this off because every write into /etc/pam.d hung
  # behind an unanswered "Allow Terminal to find devices on local network"
  # dialog; that dialog was answered on 2026-09-10 and the write path is clear.
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };

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
