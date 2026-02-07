{
  pkgs,
  lib,
  ...
}: let
  sharedVariables = import ../../../shared_variables.nix;
  # Keep this as a Nix value (not a Hyprland `$var`) so binds don't depend on
  # Hyprland variable ordering in the generated config.
  mainMod = "SUPER";
  # This will make it so that when you press $mainMod + alt + {letter} it will open up the corresponding application
  appKeyboardShortcuts = {
    anki = "A";
    spotify = "S";
    discord = "D";
    obsidian = "O";
    thunderbird = "M";
    slack = "K";
    "calendar.google.com" = "C";
    yazi = "F";
    reclaim = "R";
    btop = "B";
    nautilus = "E";
    PrusaSlicer = "P";
    cura = "U";
    "gemini.google.com" = "Y";
    whatsapp-for-linux = "W";
    "vit-todo" = "T";
    "notetaker" = "N";
    gimp = "G";
    beeper = "H";
  };
in let
  makeStringToIncaseSensitiveRegex = str: let
    # Helper function to transform a single character into a character class for both cases
    charToClass = char: "[${(lib.strings.toUpper char)}${(lib.strings.toLower char)}]";
  in
    # Transform the string into a regex pattern
    builtins.concatStringsSep "" (map charToClass (lib.strings.stringToCharacters str));

  singleton_windows = sharedVariables.singletonApplications;
  floating_windows = ["imv" ".blueman-manager-wrapped" "Volume Control" "org.speedcrunch."];

  # Mapping of application names to specific workspace numbers or names
  workspaceMapping = {
    "calendar.google.com" = "🗓️";
  };

  generateFloatingRules = floating_window: [
    "float, title:^(${floating_window})$"
    "center, title:^(${floating_window})$"
    "size 1200 725, title:^(${floating_window})$"
    "float, class:^(${floating_window})$"
    "center, class:^(${floating_window})$"
    "size 1200 725, class:^(${floating_window})$"
  ];
  generateSignletonWindowRules = singleton: let
    not_case_sensitive = makeStringToIncaseSensitiveRegex singleton;
    targetWorkspace =
      if builtins.hasAttr singleton workspaceMapping
      then "name:${workspaceMapping.${singleton}}"
      else "name:${singleton}";
  in [
    "workspace ${targetWorkspace}, class:(.*${not_case_sensitive}.*)"
    "workspace ${targetWorkspace}, title:(.*${not_case_sensitive}.*)"
  ];

  generateSingletonKeyboardShortcuts = singleton: let
    targetWorkspace =
      if builtins.hasAttr singleton workspaceMapping
      then "name:${workspaceMapping.${singleton}}"
      else "name:${singleton}";
  in
    if builtins.hasAttr singleton appKeyboardShortcuts
    then [
      "${mainMod} ALT, ${appKeyboardShortcuts.${singleton}}, exec, focus_app ${singleton} \"${targetWorkspace}\""
    ]
    else [];

  apply_function_to_content = {
    function,
    content,
  }:
    builtins.filter (x: x != "") (lib.splitString "\n" (lib.concatMapStringsSep "\n" (window: lib.concatStringsSep "\n" (function window)) content));

  generated_floating_windowrule = apply_function_to_content {
    function = generateFloatingRules;
    content = floating_windows;
  };
  generated_singleton_windowrule = apply_function_to_content {
    function = generateSignletonWindowRules;
    content = singleton_windows;
  };
  generatedSingltonKeyboardShortcuts = apply_function_to_content {
    function = generateSingletonKeyboardShortcuts;
    content = singleton_windows;
  };
in {
  wayland.windowManager.hyprland = {
    systemd = {
      variables = ["--all"];
    };
    settings = {
      # autostart
      # Keep Hyprland logs enabled so we can debug config/runtime issues.
      # If logs ever grow too large, we should fix the noisy source rather
      # than turning all logs off.
      "debug:disable_logs" = false;
      debug = {
        disable_logs = false;
      };
      exec-once = [
        "systemctl --user import-environment &"
        "hash dbus-update-activation-environment 2>/dev/null &"
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP &"
        "nm-applet &"
        "wl-clip-persist --clipboard both"
        "swaybg -m fill -i $(find ~/Pictures/wallpapers/ -maxdepth 1 -type f) &"
        "hyprctl setcursor Nordzy-cursors 22 &"
        "poweralertd &"
        "waybar &"
        "swaync &"
        "wl-paste --watch cliphist store -max-items 25000000 &"
        "gammastep -l  50:-95.2062 -t 5400:2500 -b 1:.7 &"
        # "GDK_BACKEND=x11 io.github.alainm23.planify &"
        # "sudo logkeys --start --device event0 --output $HOME/notes/life-logging/key-logging/keyboard.log &"

        "aw-server & "
        "aw-watcher-window > /home/matth/log_for_aw.txt"
        "aw-watcher-afk > /home/matth/log_for_aw1.txt"
        "hyprlock"
        "/home/matth/Projects/LifeLogging/result/bin/lifelog --config /home/matth/Projects/LifeLogging/config.toml"
        # "lifelog-logger &"
      ];

      # device-specific configurations
      # "pixa3838:00-093a:3838-touchpad" = {
      #   sensitivity = 0.0;
      #   natural_scroll = true;
      #   tap_button_map = "lrm";
      #   clickfinger_behavior = true;
      #   middle_button_emulation = true;
      #   tap-to-click = true;
      #   tap-and-drag = true;
      #   drag_lock = false;
      #   scroll_method = "2fg";
      # };
      #
      # Fixed device configuration section
      "device" = [
        {
          "name" = "pixa3838:00-093a:3838-touchpad";
          sensitivity = 0.25;
          natural_scroll = true;
          tap_button_map = "lrm";
          clickfinger_behavior = true;
          middle_button_emulation = true;
          tap-to-click = true;
          tap-and-drag = true;
          drag_lock = false;
          scroll_method = "2fg";
        }
        {
          "name" = "pixa3838:00-093a:3838-mouse";
          sensitivity = 0.25;
          natural_scroll = true;
          middle_button_emulation = true;
        }
        {
          "name" = "wingcool-inc.-touchscreen";
          output = "DP-1";
        }
        {
          "name" = "wingcool-inc.-touchscreen-1";
          output = "DP-1";
        }
      ];

      input = {
        kb_layout = "pl,us";
        kb_options = "grp:alt_caps_toggle";
        numlock_by_default = true;
        follow_mouse = 1;
        sensitivity = 0.25;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
          tap-and-drag = true;
          drag_lock = false;
          middle_button_emulation = true;
          scroll_factor = 0.5;
          clickfinger_behavior = true;
          # scroll_method = "2fg";
          tap_button_map = "lrm";
        };

        touchdevice = {
          output = "eDP-1";
          transform = 0;
        };
      };

      general = {
        layout = "dwindle";
        gaps_in = 0;
        gaps_out = 0;
        border_size = 2;
        "col.active_border" = "rgb(cba6f7) rgb(94e2d5) 45deg";
        "col.inactive_border" = "0x00000000";
      };

      misc = {
        disable_autoreload = false;
        disable_hyprland_logo = true;
        always_follow_on_dnd = true;
        layers_hog_keyboard_focus = true;
        animate_manual_resizes = false;
        enable_swallow = true;
        focus_on_activate = true;
        initial_workspace_tracking = 0;
        vfr = true;
      };

      dwindle = {
        # no_gaps_when_only = true;
        force_split = 0;
        special_scale_factor = 1.0;
        split_width_multiplier = 1.0;
        use_active_for_splits = true;
        pseudotile = "yes";
        preserve_split = "yes";
      };

      master = {
        new_status = "master";
        special_scale_factor = 1;
        # no_gaps_when_only = false;
      };

      decoration = {
        rounding = 2;
        # active_opacity = 0.90;
        # inactive_opacity = 0.75;

        fullscreen_opacity = 1.0;

        blur = {
          enabled = false;
          size = 2;
          passes = 2;
          brightness = 1;
          contrast = 1.400;
          ignore_opacity = true;
          noise = 0;
          new_optimizations = true;
          xray = true;
        };
        shadow = {
          enabled = false;
        };

        # shadow = {
        #   ignore_window = true;
        #   offset = "0 2";
        #   range = 20;
        #   render_power = 3;
        # };
      };

      animations = {
        enabled = false;

        bezier = [
          "fluent_decel, 0, 0.2, 0.4, 1"
          "easeOutCirc, 0, 0.55, 0.45, 1"
          "easeOutCubic, 0.33, 1, 0.68, 1"
          "easeinoutsine, 0.37, 0, 0.63, 1"
        ];

        animation = [
          # Windows
          "windowsIn, 1, 3, easeOutCubic, popin 30%" # window open
          "windowsOut, 1, 3, fluent_decel, popin 70%" # window close.
          "windowsMove, 1, 2, easeinoutsine, slide" # everything in between, moving, dragging, resizing.

          # Fade
          "fadeIn, 1, 2, easeOutCubic" # fade in (open) -> layers and windows
          "fadeOut, 1, 2, easeOutCubic" # fade out (close) -> layers and windows
          "fadeSwitch, 0, 1, easeOutCirc" # fade on changing activewindow and its opacity
          "fadeShadow, 1, 10, easeOutCirc" # fade on changing activewindow for shadows
          "fadeDim, 1, 4, fluent_decel" # the easing of the dimming of inactive windows
          "border, 1, 2.7, easeOutCirc" # for animating the border's color switch speed
          "borderangle, 1, 30, fluent_decel, once" # for animating the border's gradient angle - styles: once (default), loop
          "workspaces, 1, 4, easeOutCubic, fade" # styles: slide, slidevert, fade, slidefade, slidefadevert
        ];
      };

      binds = {
        movefocus_cycles_fullscreen = false;
      };
      cursor = {
        hide_on_key_press = true;
        # Hardware cursors are the fast path. Disabling them can cause high CPU
        # usage on cursor movement (especially at high refresh rates).
        no_hardware_cursors = false;
      };
      bind =
        generatedSingltonKeyboardShortcuts
        ++ [
          # show keybinds list
          "${mainMod}, F1, exec, show-keybinds"
          "${mainMod}, delete, exit"

          # keybindings
          # Avoid relying on the default tmux socket path/name. If the default
          # socket is stale/unreachable, tmux can exit immediately and kitty
          # closes right away (looks like "terminal dies").
          #
          # Always create a fresh session (do not attach to an existing one).
          "${mainMod}, T, exec, kitty -e tmux -L hypr new-session"
          "${mainMod} SHIFT, T, exec, kitty --title float_kitty"
          # "$mainMod SHIFT, T, exec, kitty --start-as=fullscreen -o 'font_size=16'"
          "${mainMod}, Q, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch killactive' 'kill-window-and-switch'"
          "${mainMod}, F, fullscreen, 0"
          "${mainMod} SHIFT, F, fullscreen, 1"
          "${mainMod}, Space, togglefloating,"
          "${mainMod}, A, exec, fuzzel"
          "${mainMod}, Escape, exec, systemctl suspend"
          "${mainMod}, E, exec, wofi-emoji"
          "${mainMod} SHIFT, Escape, exec, shutdown-script"
          "${mainMod}, P, pseudo,"
          "${mainMod}, S, togglesplit,"
          "${mainMod} SHIFT, B, exec, pkill -SIGUSR1 .waybar-wrapped"
          "${mainMod}, C ,exec, hyprpicker -a"
          "${mainMod}, W,exec, wallpaper-picker"
          "${mainMod} SHIFT, W, exec, vm-start"
          "${mainMod}, B, exec, zen"
          "${mainMod}, Y, exec, swaync-client --close-latest"

          "${mainMod} SHIFT, R, exec, notify-send -t 2000 -u normal -i dialog-information \"Starting rebuild 👷!\" \"\" && rebuild && notify-if-command-is-successful rebuild"

          ",XF86AudioLowerVolume, exec, pamixer --decrease 5"
          ",XF86AudioRaiseVolume, exec, pamixer --increase 5"

          ", XF86Calculator, exec, speedcrunch"

          # screenshot
          "ALT, Print, exec, ocr-screenshot && wl-paste -t text/plain > ~/Pictures/Screenshots/$(date +'%Y-%m-%d-%Ih%Mm%Ss').txt"
          ",Print, exec, grimblast --notify --freeze copy area && wl-paste -t image/png > ~/Pictures/Screenshots/$(date +'%Y-%m-%d-%Ih%Mm%Ss').png"

          "${mainMod}, N, exec, ~/Projects/KnowledgeManagementSystem/result/bin/kms-capture"

          # Move focus with mainMod + arrow keys
          # "$mainMod, h, changegroupactive, back"
          # "$mainMod, l, changegroupactive, forward"
          "${mainMod}, h, movefocus, l"
          "${mainMod}, l, movefocus, r"
          "${mainMod}, k, movefocus, u"
          "${mainMod}, j, movefocus, d"
          # "$mainMod, Q, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch killactive' 'kill-window-and-switch'"

          "${mainMod} SHIFT, h, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow l' 'switch-workspace-to-other-monitor'"
          "${mainMod} SHIFT, l, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow r' 'switch-workspace-to-other-monitor'"
          "${mainMod} SHIFT, k, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow u' 'switch-workspace-to-other-monitor'"
          "${mainMod} SHIFT, j, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow d' 'switch-workspace-to-other-monitor'"

          "${mainMod} SHIFT, right, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow l' 'switch-workspace-to-other-monitor'"
          "${mainMod} SHIFT, left, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow r' 'switch-workspace-to-other-monitor'"
          "${mainMod} SHIFT, up, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow u' 'switch-workspace-to-other-monitor'"
          "${mainMod} SHIFT, down, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow d' 'switch-workspace-to-other-monitor'"

          # switch workspace
          "${mainMod}, 1, workspace, 1"
          "${mainMod}, 2, workspace, 2"
          "${mainMod}, 3, workspace, 3"
          "${mainMod}, 4, workspace, 4"
          "${mainMod}, 5, workspace, 5"
          "${mainMod}, 6, workspace, 6"
          "${mainMod}, 7, workspace, 7"
          "${mainMod}, 8, workspace, 8"
          "${mainMod}, 9, workspace, 9"
          "${mainMod}, 0, workspace, 10"

          # Resize windows
          "${mainMod} SHIFT, right, resizeactive, 30 0"
          "${mainMod} SHIFT, left, resizeactive, -30 0"
          "${mainMod} SHIFT, up, resizeactive, 0 -30"
          "${mainMod} SHIFT, down, resizeactive, 0 30"

          # Switch workspaces with mainMod + [0-9]
          "${mainMod}, 1, workspace, 1"
          "${mainMod}, 2, workspace, 2"
          "${mainMod}, 3, workspace, 3"
          "${mainMod}, 4, workspace, 4"
          "${mainMod}, 5, workspace, 5"
          "${mainMod}, 6, workspace, 6"
          "${mainMod}, 7, workspace, 7"
          "${mainMod}, 8, workspace, 8"
          "${mainMod}, 9, workspace, 9"
          "${mainMod}, 0, workspace, 10"
          "${mainMod} ALT, 1, workspace, 11"
          "${mainMod} ALT, 2, workspace, 12"
          "${mainMod} ALT, 3, workspace, 13"
          "${mainMod} ALT, 4, workspace, 14"
          "${mainMod} ALT, 5, workspace, 15"
          "${mainMod} ALT, 6, workspace, 16"
          "${mainMod} ALT, 7, workspace, 17"
          "${mainMod} ALT, 8, workspace, 18"
          "${mainMod} ALT, 9, workspace, 19"
          "${mainMod} ALT, 0, workspace, 20"

          # Move active window to a workspace with mainMod + SHIFT + [0-9]
          "${mainMod} SHIFT, 1, movetoworkspacesilent, 1"
          "${mainMod} SHIFT, 2, movetoworkspacesilent, 2"
          "${mainMod} SHIFT, 3, movetoworkspacesilent, 3"
          "${mainMod} SHIFT, 4, movetoworkspacesilent, 4"
          "${mainMod} SHIFT, 5, movetoworkspacesilent, 5"
          "${mainMod} SHIFT, 6, movetoworkspacesilent, 6"
          "${mainMod} SHIFT, 7, movetoworkspacesilent, 7"
          "${mainMod} SHIFT, 8, movetoworkspacesilent, 8"
          "${mainMod} SHIFT, 9, movetoworkspacesilent, 9"
          "${mainMod} SHIFT, 0, movetoworkspacesilent, 10"
          "${mainMod} SHIFT ALT, 1, movetoworkspacesilent, 11"
          "${mainMod} SHIFT ALT, 2, movetoworkspacesilent, 12"
          "${mainMod} SHIFT ALT, 3, movetoworkspacesilent, 13"
          "${mainMod} SHIFT ALT, 4, movetoworkspacesilent, 14"
          "${mainMod} SHIFT ALT, 5, movetoworkspacesilent, 15"
          "${mainMod} SHIFT ALT, 6, movetoworkspacesilent, 16"
          "${mainMod} SHIFT ALT, 7, movetoworkspacesilent, 17"
          "${mainMod} SHIFT ALT, 8, movetoworkspacesilent, 18"
          "${mainMod} SHIFT ALT, 9, movetoworkspacesilent, 19"
          "${mainMod} SHIFT ALT, 0, movetoworkspacesilent, 20"

          # media and volume controls
          ",XF86AudioRaiseVolume,exec, pamixer -i 2"
          ",XF86AudioLowerVolume,exec, pamixer -d 2"
          ",XF86AudioMute,exec, pamixer -t"
          ",XF86AudioPlay,exec, playerctl play-pause"
          ",XF86AudioNext,exec, playerctl next"
          ",XF86AudioPrev,exec, playerctl previous"
          ",XF86AudioStop, exec, playerctl stop"
          "${mainMod}, mouse_down, workspace, e-1"
          "${mainMod}, mouse_up, workspace, e+1"
          "${mainMod} SHIFT CONTROL, q, exec, reboot"

          ", KP_1, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --copy"
          ", KP_End, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --copy"
          ", KP_2, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --type"
          ", KP_Down, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --type"
          ", KP_4, exec, wl-paste | /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/prompt-llm.py | wl-copy ; notify-send -u normal -i dialog-information 'Copied to clipboard' ''"
          ", KP_Left, exec, wl-paste | /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/prompt-llm.py | wl-copy ; notify-send -u normal -i dialog-information 'Copied to clipboard' ''"
          ", KP_Begin, exec, prompt-picker"
          ", KP_5, exec, prompt-picker"
          ", KP_7, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/open-website-as-standalone-app.sh 'https://gemini.google.com/gem/6dbcf84e326c'"
          ", KP_Home, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/open-website-as-standalone-app.sh 'https://gemini.google.com/gem/6dbcf84e326c'"

          "${mainMod}, Tab, focuscurrentorlast"
          # laptop brigthness
          ",XF86MonBrightnessUp, exec, brightness -i 1"
          ",XF86MonBrightnessDown, exec, brightness -d 1"
          "SHIFT,XF86MonBrightnessUp, exec, brightness -i 10"
          "SHIFT,XF86MonBrightnessDown, exec, brightness -d 10"
          "CONTROL,XF86MonBrightnessUp, exec, hyprctl dispatch dpms on" # turn displays on
          "CONTROL,XF86MonBrightnessDown, exec, hyprctl dispatch dpms off"
          "SHIFT CONTROL ALT,XF86MonBrightnessUp, exec, secondary-monitor-update"
          "SHIFT CONTROL ALT,XF86MonBrightnessDown, exec, secondary-monitor-update"
          "${mainMod}, XF86MonBrightnessUp, exec, brightness -s 100"
          "${mainMod}, XF86MonBrightnessDown, exec, brightness -s 0"
          # # make it so control alt v pastes the second item in clipboard history without changing the clipboard history
          "CONTROL ALT, V, exec, wtype -m ctrl -m alt \"v\" (cliphist list | head -n 2) | tail -n 1 | cliphist decode | wl-copy ; wtype -M ctrl \"v\" ; sleep 0.05 ; wtype -m ctrl \"v\" ; (cliphist list | head -n 2) | tail -n 1 | cliphist decode | wl-copy"
          "SHIFT CONTROL ALT, V, exec, wtype -m shift -m ctrl -m alt \"v\" (cliphist list | head -n 2) | tail -n 1 | cliphist decode | wl-copy ; wtype -M shift -M ctrl \"v\" ; sleep 0.05 ; wtype -m ctrl \"v\" ; (cliphist list | head -n 2) | tail -n 1 | cliphist decode | wl-copy"

          "SUPER SHIFT, $copilot, exec, focus_app gemini.google.com"

          # clipboard manager
          "${mainMod}, V, exec, cliphist list -max-iterms 1000 -preview-width 1000 | fuzzel --dmenu | cliphist decode | wl-copy"

          "${mainMod} SHIFT, F23, exec, notify-send -t 2000 -u normal -i dialog-information \"Starting rebuild 👷!\" \"\""
        ];

      # mouse binding
      bindm = [
        "${mainMod}, mouse:272, movewindow"
        "${mainMod}, mouse:273, resizewindow"
      ];

      # windowrule - keeping minimal legacy rules
      windowrule = [];

      # windowrulev2
      windowrulev2 =
        generated_singleton_windowrule
        ++ generated_floating_windowrule
        ++ [
          "workspace name:gemini, class:.*(gemini).*"
          "workspace name:gemini, title:.*(gemini).*"
          # Legacy windowrule entries moved to windowrulev2
          "tile, class:^(Aseprite)$"
          "float, title:^(float_kitty)$"
          "center, title:^(float_kitty)$"
          "size 950 600, title:^(float_kitty)$"

          "float, class:^(audacious)$"
          "tile, class:^(neovide)$"
          "idleinhibit focus, class:^(mpv)$"
          "float, class:^(udiskie)$"
          "float, title:^(Transmission)$"
          "float, title:^(Volume Control)$"
          "float, title:^(Firefox — Sharing Indicator)$"
          "move 0 0, title:^(Firefox — Sharing Indicator)$"
          "size 700 450, title:^(Volume Control)$"
          "workspace name:🗓️, title:(calendar)"
          "workspace name:🗓️, class:.*(chrome-calendar.google.com).*"
          "workspace name:notetaker, title:(notetaker)"
          "move 40 55%, title:^(Volume Control)$"

          "float, title:^(knowledge-management-system-capture)$"
          "size 875 875, title:^(knowledge-management-system-capture)$"
        ]
        ++ [
          "float, title:^(Picture-in-Picture)$"
          "opacity 1.0 override 1.0 override, title:^(Picture-in-Picture)$"
          "pin, title:^(Picture-in-Picture)$"
          "opacity 1.0 override 1.0 override, title:^(.*imv.*)$"
          "opacity 1.0 override 1.0 override, title:^(.*mpv.*)$"
          "opacity 1.0 override 1.0 override, class:(Aseprite)"
          "opacity 1.0 override 1.0 override, class:(Unity)"
          "idleinhibit focus, class:^(mpv)$"
          "idleinhibit fullscreen, class:^(firefox)$"
          "float,class:^(zenity)$"
          "center,class:^(zenity)$"
          "size 850 500,class:^(zenity)$"
          "float,class:^(pavucontrol)$"
          "float,class:^(SoundWireServer)$"
          "float,class:^(.sameboy-wrapped)$"
          "float,class:^(file_progress)$"
          "float,class:^(confirm)$"
          "float,class:^(dialog)$"
          "float,class:^(download)$"
          "float,class:^(notification)$"
          "float,class:^(error)$"
          "float,class:^(confirmreset)$"
          "float,title:^(Open File)$"
          "float,title:^(branchdialog)$"
          "float,title:^(Confirm to replace files)$"
          "float,title:^(File Operation Progress)$"

          "opacity 0.0 override,class:^(xwaylandvideobridge)$"
          "noanim,class:^(xwaylandvideobridge)$"
          "noinitialfocus,class:^(xwaylandvideobridge)$"
          "maxsize 1 1,class:^(xwaylandvideobridge)$"
          "noblur,class:^(xwaylandvideobridge)$"

          # "workspace, 10, class:^(.*)(discord)(.*)$"
          # "workspace 10, class:^(.*)(discord)(.*)$"
        ];
    };

    extraConfig = "

# # # tablet mode
#       monitor=eDP-1,preferred,0x0,1.0
#       # monitor=DP-1,3840x2400,0x1080,auto, transform, 2
#       monitor=DP-1,preferred,0x1080,1.0

      monitor=eDP-1,preferred,0x0,1
      monitor=DP-1,preferred,2880x0,0.5
      monitor=HDMI-A-1,preferred,-1920x0,1.0

      # this

      # workslpaces 1-10 on primary minotir
      workspace=1, monitor:eDP-1
      workspace=2, monitor:eDP-1
      workspace=3, monitor:eDP-1
      workspace=4, monitor:eDP-1
      workspace=5, monitor:eDP-1
      workspace=6, monitor:eDP-1
      workspace=7, monitor:eDP-1
      workspace=8, monitor:eDP-1
      workspace=9, monitor:eDP-1
      workspace=10, monitor:eDP-1


      # # all workspaces on secondary monitor
      # workspace=1, monitor:DP-1
      # workspace=2, monitor:DP-1
      # workspace=3, monitor:DP-1
      # workspace=4, monitor:DP-1
      # workspace=5, monitor:DP-1
      # workspace=6, monitor:DP-1
      # workspace=7, monitor:DP-1
      # workspace=8, monitor:DP-1
      # workspace=9, monitor:DP-1
      # workspace=10, monitor:DP-1

      # workspace=11, monitor:DP-1
      # workspace=12, monitor:DP-1
      # workspace=13, monitor:DP-1
      # workspace=14, monitor:DP-1
      # workspace=15, monitor:DP-1
      # workspace=16, monitor:DP-1
      # workspace=17, monitor:DP-1
      # workspace=18, monitor:DP-1
      # workspace=19, monitor:DP-1
      # workspace=20, monitor:DP-1

      workspace=11, monitor:HDMI-A-1
      workspace=12, monitor:HDMI-A-1
      workspace=13, monitor:HDMI-A-1
      workspace=14, monitor:HDMI-A-1
      workspace=15, monitor:HDMI-A-1
      workspace=16, monitor:HDMI-A-1
      workspace=17, monitor:HDMI-A-1
      workspace=18, monitor:HDMI-A-1
      workspace=19, monitor:HDMI-A-1
      workspace=20, monitor:HDMI-A-1
      #
      # monitor=eDP-1,preferred,0x0,1.0
      # monitor=DP-1,preferred,1920x0,1.0
      # monitor=HDMI-A-1,preferred,-2560x-1440,1.0


gestures {
  # workspace_swipe = on
  workspace_swipe_cancel_ratio = 0.15
}

    plugin:touch_gestures {
  # The default sensitivity is probably too low on tablet screens,
  # I recommend turning it up to 4.0
  sensitivity = 2.0

  # must be >= 3
  workspace_swipe_fingers = 3

  # switching workspaces by swiping from an edge, this is separate from workspace_swipe_fingers
  # and can be used at the same time
  # possible values: l, r, u, or d
  # to disable it set it to anything else
  workspace_swipe_edge = d

  # in milliseconds
  long_press_delay = 400

  # in pixels, the distance from the edge that is considered an edge
  edge_margin = 15

  experimental {
    # send proper cancel events to windows instead of hacky touch_up events,
    # NOT recommended as it crashed a few times, once it's stabilized I'll make it the default
    send_cancel = 0
  }
}

      
plugin:touch_gestures {
    # swipe left from right edge
    hyprgrass-bind = , edge:r:l, workspace, +1
    hyprgrass-bind = , edge:l:r, workspace, -1

    # swipe up from bottom edge
    hyprgrass-bind = , edge:d:u, exec, firefox

    # swipe down from left edge
    hyprgrass-bind = , edge:l:d, exec, pactl set-sink-volume @DEFAULT_SINK@ -4%

    # swipe down with 4 fingers
    # NOTE: swipe events only trigger for finger count of >= 3
    hyprgrass-bind = , swipe:4:d, killactive

    # swipe diagonally left and down with 3 fingers
    # l (or r) must come before d and u
    hyprgrass-bind = , swipe:3:ld, exec, foot

    # tap with 3 fingers
    # NOTE: tap events only trigger for finger count of >= 3
    hyprgrass-bind = , tap:3, exec, foot

    # longpress can trigger mouse binds:
    hyprgrass-bindm = , longpress:2, movewindow
    hyprgrass-bindm = , longpress:3, resizewindow
}
    ";
  };
}
