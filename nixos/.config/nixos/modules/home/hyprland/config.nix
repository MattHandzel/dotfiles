{lib, ...}: let
  sharedVariables = import ../../../shared_variables.nix;
  appKeyboardShortcuts = {
    spotify = "S";
    discord = "D";
    obsidian = "O";
    thunderbird = "M";
    slack = "K";
    morgen = "C";
    nautilus = "F";
  };
in let
  makeStringToIncaseSensitiveRegex = str: let
    # Helper function to transform a single character into a character class for both cases
    charToClass = char: "[${(lib.strings.toUpper char)}${(lib.strings.toLower char)}]";
  in
    # Transform the string into a regex pattern
    builtins.concatStringsSep "" (map charToClass (lib.strings.stringToCharacters str));

  singleton_windows = sharedVariables.singletonApplications;
  floating_windows = ["imv" "mpv" ".blueman-manager-wrapped" "Volume Control"];
  generateFloatingRules = floating_window: [
    "float,${floating_window}"
    "center,${floating_window}"
    "size 1200 725,${floating_window}"
  ];
  generateSignletonWindowRules = singleton: let
    not_case_sensitive = makeStringToIncaseSensitiveRegex singleton;
  in [
    "workspace name:${singleton}, class:(${not_case_sensitive})"
  ];

  generateSingletonKeyboardShortcuts = singleton:
    if builtins.hasAttr singleton appKeyboardShortcuts
    then [
      "$mainMod ALT, ${appKeyboardShortcuts.${singleton}}, exec, focus_app ${singleton}"
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
        "syncthing &"
        "wl-paste --watch copy-to-clipboard &"
        "gammastep -l  50.1047:-110.2062 -t 5700:1500 -b 1:.6  &"
        "hyprlock"
        "sudo chmod 666 /dev/i2c-*"
      ];

      input = {
        kb_layout = "us,fr";
        kb_options = "grp:alt_caps_toggle";
        numlock_by_default = true;
        follow_mouse = 1;
        sensitivity = 0.7;
        touchpad = {
          natural_scroll = true;
        };
        touchdevice = {
          output = "eDP-1";
          # name = "04f31234:00-1fd2:8008";
        };
        # {
        #   output = "DP-1";
        #   name = "wingcool-inc.-touchscreen-1";
        # }

        # ];
        # "device" = {
        #   "dell0a78:00-27c6:0d42-touchpad" = {
        #     tap-to-click = true;
        #     natural-scroll = true;
        #     scroll-method = "two-finger";
        #     # other options...
        #   };
        # };
      };

      general = {
        "$mainMod" = "SUPER";
        "$term" = "kitty";
        "$file" = "dolphin";
        "$browser" = "zen";

        layout = "dwindle";
        gaps_in = 0;
        gaps_out = 0;
        border_size = 2;
        "col.active_border" = "rgb(cba6f7) rgb(94e2d5) 45deg";
        "col.inactive_border" = "0x00000000";
        border_part_of_window = false;
        no_border_on_floating = false;
      };

      misc = {
        disable_autoreload = false;
        disable_hyprland_logo = true;
        always_follow_on_dnd = true;
        layers_hog_keyboard_focus = true;
        animate_manual_resizes = false;
        enable_swallow = true;
        focus_on_activate = true;
        new_window_takes_over_fullscreen = 1;
        initial_workspace_tracking = 0;
      };

      dwindle = {
        no_gaps_when_only = true;
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
        no_gaps_when_only = false;
      };

      decoration = {
        rounding = 0;
        # active_opacity = 0.90;
        inactive_opacity = 1.0;

        fullscreen_opacity = 1.0;

        blur = {
          enabled = false;
          size = 1;
          passes = 1;
          # size = 4;
          # passes = 2;
          brightness = 1;
          contrast = 1.400;
          ignore_opacity = true;
          noise = 0;
          new_optimizations = true;
          xray = true;
        };

        drop_shadow = true;

        shadow_ignore_window = true;
        shadow_offset = "0 2";
        shadow_range = 20;
        shadow_render_power = 3;
        "col.shadow" = "rgba(00000055)";
      };

      animations = {
        enabled = true;

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
      };
      bind =
        generatedSingltonKeyboardShortcuts
        ++ [
          # show keybinds list
          "$mainMod, F1, exec, show-keybinds"
          "$mainMod, delete, exit"

          # keybindings
          "$mainMod, T, exec, kitty"
          "$mainMod SHIFT, T, exec, kitty --title float_kitty"
          # "$mainMod SHIFT, T, exec, kitty --start-as=fullscreen -o 'font_size=16'"
          "$mainMod, Q, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch killactive' 'kill-window-and-switch'"
          "$mainMod, F, fullscreen, 0"
          "$mainMod SHIFT, F, fullscreen, 1"
          "$mainMod, Space, togglefloating,"
          "$mainMod, A, exec, fuzzel"
          "$mainMod, Escape, exec, systemctl suspend"
          "$mainMod SHIFT, Escape, exec, shutdown-script"
          "$mainMod, E, exec, wofi-emoji"
          "$mainMod, P, pseudo,"
          "$mainMod, S, togglesplit,"
          "$mainMod SHIFT, B, exec, pkill -SIGUSR1 .waybar-wrapped"
          "$mainMod, C ,exec, hyprpicker -a"
          "$mainMod, W,exec, wallpaper-picker"
          "$mainMod SHIFT, W, exec, vm-start"

          "$mainMod SHIFT, R, exec, notify-send -t 2000 -u normal -i dialog-information \"Starting rebuild 👷!\" \"\" && rebuild && notify-if-command-is-successful rebuild"

          ",XF86AudioLowerVolume, exec, pamixer --decrease 5"
          ",XF86AudioRaiseVolume, exec, pamixer --increase 5"

          # screenshot
          "ALT, Print, exec, grimblast --notify --cursor --freeze save area ~/Pictures/$(date +'%Y-%m-%d-At-%Ih%Mm%Ss').png"
          ",Print, exec, grimblast --notify --cursor --freeze copy area"

          "$mainMod, N, exec, quick-capture"
          "$mainMod ALT, N, exec, quick-capture"

          # Move focus with mainMod + arrow keys
          # "$mainMod, h, changegroupactive, back"
          # "$mainMod, l, changegroupactive, forward"
          "$mainMod, h, movefocus, l"
          "$mainMod, l, movefocus, r"
          "$mainMod, k, movefocus, u"
          "$mainMod, j, movefocus, d"
          # "$mainMod, Q, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch killactive' 'kill-window-and-switch'"

          "$mainMod SHIFT , h, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow l' 'switch-workspace-to-other-monitor'"
          "$mainMod SHIFT , l, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow r' 'switch-workspace-to-other-monitor'"
          "$mainMod SHIFT , k, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow u' 'switch-workspace-to-other-monitor'"
          "$mainMod SHIFT , j, exec, run-command-based-on-type-of-workspace 'hyprctl dispatch movewindow d' 'switch-workspace-to-other-monitor'"

          # Switch workspaces relative to the active workspace with mainMod + CTRL + [←→]
          "$mainMod CTRL, right, workspace, r+1"
          "$mainMod CTRL, left, workspace, r-1"

          # switch workspace
          "$mainMod, 1, workspace, 1"
          "$mainMod, 2, workspace, 2"
          "$mainMod, 3, workspace, 3"
          "$mainMod, 4, workspace, 4"
          "$mainMod, 5, workspace, 5"
          "$mainMod, 6, workspace, 6"
          "$mainMod, 7, workspace, 7"
          "$mainMod, 8, workspace, 8"
          "$mainMod, 9, workspace, 9"
          "$mainMod, 0, workspace, 10"

          # Resize windows
          "$mainMod SHIFT, right, resizeactive, 30 0"
          "$mainMod SHIFT, left, resizeactive, -30 0"
          "$mainMod SHIFT, up, resizeactive, 0 -30"
          "$mainMod SHIFT, down, resizeactive, 0 30"

          # Switch workspaces with mainMod + [0-9]
          "$mainMod, 1, workspace, 1"
          "$mainMod, 2, workspace, 2"
          "$mainMod, 3, workspace, 3"
          "$mainMod, 4, workspace, 4"
          "$mainMod, 5, workspace, 5"
          "$mainMod, 6, workspace, 6"
          "$mainMod, 7, workspace, 7"
          "$mainMod, 8, workspace, 8"
          "$mainMod, 9, workspace, 9"
          "$mainMod, 0, workspace, 10"
          "$mainMod ALT, 1, workspace, 11"
          "$mainMod ALT, 2, workspace, 12"
          "$mainMod ALT, 3, workspace, 13"
          "$mainMod ALT, 4, workspace, 14"
          "$mainMod ALT, 5, workspace, 15"
          "$mainMod ALT, 6, workspace, 16"
          "$mainMod ALT, 7, workspace, 17"
          "$mainMod ALT, 8, workspace, 18"
          "$mainMod ALT, 9, workspace, 19"
          "$mainMod ALT, 0, workspace, 20"

          # Move active window to a workspace with mainMod + SHIFT + [0-9]
          "$mainMod SHIFT, 1, movetoworkspacesilent, 1"
          "$mainMod SHIFT, 2, movetoworkspacesilent, 2"
          "$mainMod SHIFT, 3, movetoworkspacesilent, 3"
          "$mainMod SHIFT, 4, movetoworkspacesilent, 4"
          "$mainMod SHIFT, 5, movetoworkspacesilent, 5"
          "$mainMod SHIFT, 6, movetoworkspacesilent, 6"
          "$mainMod SHIFT, 7, movetoworkspacesilent, 7"
          "$mainMod SHIFT, 8, movetoworkspacesilent, 8"
          "$mainMod SHIFT, 9, movetoworkspacesilent, 9"
          "$mainMod SHIFT, 0, movetoworkspacesilent, 10"
          "$mainMod SHIFT ALT, 1, movetoworkspacesilent, 11"
          "$mainMod SHIFT ALT, 2, movetoworkspacesilent, 12"
          "$mainMod SHIFT ALT, 3, movetoworkspacesilent, 13"
          "$mainMod SHIFT ALT, 4, movetoworkspacesilent, 14"
          "$mainMod SHIFT ALT, 5, movetoworkspacesilent, 15"
          "$mainMod SHIFT ALT, 6, movetoworkspacesilent, 16"
          "$mainMod SHIFT ALT, 7, movetoworkspacesilent, 17"
          "$mainMod SHIFT ALT, 8, movetoworkspacesilent, 18"
          "$mainMod SHIFT ALT, 9, movetoworkspacesilent, 19"
          "$mainMod SHIFT ALT, 0, movetoworkspacesilent, 20"

          # media and volume controls
          ",XF86AudioRaiseVolume,exec, pamixer -i 2"
          ",XF86AudioLowerVolume,exec, pamixer -d 2"
          ",XF86AudioMute,exec, pamixer -t"
          ",XF86AudioPlay,exec, playerctl play-pause"
          ",XF86AudioNext,exec, playerctl next"
          ",XF86AudioPrev,exec, playerctl previous"
          ",XF86AudioStop, exec, playerctl stop"
          "$mainMod, mouse_down, workspace, e-1"
          "$mainMod, mouse_up, workspace, e+1"
          "$mainMod SHIFT CONTROL, q, exec, reboot"

          "$mainMod, Tab, focuscurrentorlast"
          # laptop brigthness
          ",XF86MonBrightnessUp, exec, brightness -i 1"
          ",XF86MonBrightnessDown, exec, brightness -d 1"
          "SHIFT,XF86MonBrightnessUp, exec, brightness -i 10"
          "SHIFT,XF86MonBrightnessDown, exec, brightness -d 10"
          "CONTROL,XF86MonBrightnessUp, exec, wlr-randr --output DP-1 --on && wlr-randr --output eDP-1 --on" # turn displays off
          "CONTROL,XF86MonBrightnessDown, exec, wlr-randr --output DP-1 --off && wlr-randr --output eDP-1 --off"
          "SHIFT CONTROL ALT,XF86MonBrightnessUp, exec, secondary-monitor-update"
          "SHIFT CONTROL ALT,XF86MonBrightnessDown, exec, secondary-monitor-update"
          "$mainMod, XF86MonBrightnessUp, exec, brightness -s 100"
          "$mainMod, XF86MonBrightnessDown, exec, brightness -s 0"

          # clipboard manager
          "$mainMod, V, exec, cliphist list | fuzzel --dmenu | cliphist decode | wl-copy"
        ];

      # mouse binding
      bindm = [
        "$mainMod, mouse:272, movewindow"
        "$mainMod, mouse:273, resizewindow"
      ];

      # windowrule
      windowrule =
        generated_floating_windowrule
        ++ [
          "tile,Aseprite"
          "float,title:^(float_kitty)$"
          "center,title:^(float_kitty)$"
          "size 950 600,title:^(float_kitty)$"

          "float,audacious"
          # "pin,wofi"
          # "float,wofi"
          # "noborder,wofi"
          "tile, neovide"
          "idleinhibit focus,mpv"
          "float,udiskie"
          "float,title:^(Transmission)$"
          "float,title:^(Volume Control)$"
          "float,title:^(Firefox — Sharing Indicator)$"
          "move 0 0,title:^(Firefox — Sharing Indicator)$"
          "size 700 450,title:^(Volume Control)$"
          "move 40 55%,title:^(Volume Control)$"
        ];

      # windowrulev2
      windowrulev2 =
        generated_singleton_windowrule
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
# tablet mode
      # monitor=eDP-1,preferred,0x0,1.0
      # monitor=DP-1,1920x1080,0x1080,auto
# monitor mode
      monitor=eDP-1,preferred,1920x0,1.0
      monitor=DP-1,1920x1080,0x0,auto

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


      workspace=11, monitor:DP-1
      workspace=12, monitor:DP-1
      workspace=13, monitor:DP-1
      workspace=14, monitor:DP-1
      workspace=15, monitor:DP-1
      workspace=16, monitor:DP-1
      workspace=17, monitor:DP-1
      workspace=18, monitor:DP-1
      workspace=19, monitor:DP-1
      workspace=20, monitor:DP-1
      # workspace=11, monitor:HDMI-A-1
      # workspace=12, monitor:HDMI-A-1
      # workspace=13, monitor:HDMI-A-1
      # workspace=14, monitor:HDMI-A-1
      # workspace=15, monitor:HDMI-A-1
      # workspace=16, monitor:HDMI-A-1
      # workspace=17, monitor:HDMI-A-1
      # workspace=18, monitor:HDMI-A-1
      # workspace=19, monitor:HDMI-A-1
      # workspace=20, monitor:HDMI-A-1


    ";
  };
}
