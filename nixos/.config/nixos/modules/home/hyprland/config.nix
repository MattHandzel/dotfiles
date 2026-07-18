{
  pkgs,
  lib,
  config,
  ...
}: let
  sharedVariables = import ../../../shared_variables.nix;
  p = config.theme.palette;
  # Keep this as a Nix value (not a Hyprland `$var`) so binds don't depend on
  # Hyprland variable ordering in the generated config.
  mainMod = "SUPER";
  copilotKey = "code:201";
  # This will make it so that when you press $mainMod + alt + {letter} it will open up the corresponding application
  appKeyboardShortcuts = {
    anki = "A";
    spotify = "S";
    discord = "D";
    obsidian = "O";
    betterbird = "M";
    slack = "K";
    calendar = "C";
    yazi = "F";
    btop = "B";
    dolphin = "E";
    PrusaSlicer = "P";
    cura = "U";
    "gemini.google.com" = "Y";
    wasistlos = "I"; # W now opens Wispr Flow (see the wispr-hub bind below)
    "tasker" = "T";
    "notetaker" = "N";
    gimp = "G";
    beeper = "H";
    linear = "L";
  };
in let
  makeStringToIncaseSensitiveRegex = str: let
    escapedStr = lib.replaceStrings ["."] ["\\."] str;
  in "(?i).*${escapedStr}.*";

  singleton_windows = sharedVariables.singletonApplications;
  floating_windows = ["swayimg" ".blueman-manager-wrapped" "Volume Control" "org.speedcrunch." "floating-pl" "predict-popup"];

  # Mapping of application names to specific workspace numbers or names
  workspaceMapping = {
    calendar = "calendar";
    "gemini.google.com" = "gemini";
  };

  generateFloatingRules = floating_window: [
    "float 1, match:title ^(${floating_window})$"
    "center 1, match:title ^(${floating_window})$"
    "size 1200 725, match:title ^(${floating_window})$"
    "float 1, match:class ^(${floating_window})$"
    "center 1, match:class ^(${floating_window})$"
    "size 1200 725, match:class ^(${floating_window})$"
  ];
  generateSignletonWindowRules = singleton: let
    not_case_sensitive = makeStringToIncaseSensitiveRegex singleton;
    targetWorkspace =
      if builtins.hasAttr singleton workspaceMapping
      then "${workspaceMapping.${singleton}}"
      else "${singleton}";
  in [
    "workspace name:${targetWorkspace}, match:class ^(${not_case_sensitive})$"
    "workspace name:${targetWorkspace}, match:title ^(${not_case_sensitive})$"
  ];

  generateSingletonKeyboardShortcuts = singleton: let
    targetWorkspace =
      if builtins.hasAttr singleton workspaceMapping
      then "${workspaceMapping.${singleton}}"
      else "${singleton}";
  in
    if builtins.hasAttr singleton appKeyboardShortcuts
    then [
      # Prepend 'name:' to ensure hyprctl treats it as a named workspace
      "${mainMod} ALT, ${appKeyboardShortcuts.${singleton}}, exec, focus_app ${singleton} \"name:${targetWorkspace}\""
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
      "debug:disable_logs" = true;
      debug = {
        disable_logs = true;
      };
      exec-once = [
        "systemctl --user import-environment &"
        "hash dbus-update-activation-environment 2>/dev/null &"
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP &"
        "nm-applet &"
        # Wispr Flow is NOT started here — it runs as the wispr-flow systemd user
        # service (modules/home/wispr-flow.nix) so its lifecycle can be coupled to
        # kbd-relay: Wispr enumerates keyboards once at startup, so it must start
        # after the relay's virtual keyboard and restart whenever the relay does.
        # Its Hub window is routed to the `wispr` workspace by windowrule below;
        # the floating pill is pinned + follows the cursor via wispr-pill-follow.
        "wl-clip-persist --clipboard both"
        "swaybg -m fill -i $(find ~/Pictures/wallpapers/ -maxdepth 1 -type f) &"
        "hyprctl setcursor Nordzy-cursors 22 &"
        "poweralertd &"
        "waybar &"
        "swaync &"
        "wl-paste --watch cliphist store -max-items 25000000 &"
        "gammastep -l  50:-145.2062 -t 5400:3500 -b 1:1 &"
        # "sudo logkeys --start --device event0 --output $HOME/notes/life-logging/key-logging/keyboard.log &"

        # ActivityWatch now runs as durable systemd user services
        # (modules/home/activitywatch.nix): aw-server + aw-watcher-afk +
        # aw-watcher-window-hyprland. The old exec-once launches were
        # session-scoped, spawned duplicates on relogin, and the generic
        # window watcher logged "unknown" titles on Hyprland.
        "hyprlock"
        # espanso is started by its systemd unit (WantedBy=hyprland-session.target),
        # which Hyprland's own stop/start of that target launches once the compositor
        # is up — no manual restart needed (it only added an extra ~14s re-init).
        # Runs in the low-priority app-lifelog slice (app-memory-caps.nix) so
        # its zstd/ffmpeg archival jobs can't starve the foreground apps.
        "systemd-run --user --slice=app-lifelog.slice --scope -- /home/matth/Projects/LifeLogging/result/bin/lifelog --config /home/matth/Projects/LifeLogging/config.toml"
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
          # The TOTEM's firmware sends the keys Matt actually wants (Esc is a
          # combo on the board) — exclude it from the global caps:swapescape.
          # NOTE: it enumerates under two different names — this one over
          # Bluetooth, "zmk-project-..." over USB — so BOTH need the override
          # or Esc becomes CapsLock on whichever transport is active.
          "name" = "matt's-totem-keyboard";
          kb_options = "grp:alt_caps_toggle";
        }
        {
          "name" = "zmk-project-matt's-totem-keyboard";
          kb_options = "grp:alt_caps_toggle";
        }
        {
          # kbd-relay (modules/home/kbd-relay.nix) re-emits the TOTEM through
          # this always-present virtual keyboard for Wispr Flow — so it needs
          # the same exclusion, or the global caps:swapescape maps the TOTEM's
          # Esc to CapsLock (bit Matt 2026-07-15).
          "name" = "keyboard-relay";
          kb_options = "grp:alt_caps_toggle";
        }
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
        # Plain us (QWERTY) at the xkb level. The custom Corne layout is produced by
        # kanata (modules/core/kanata-homerow.nix), which remaps physical keys BEFORE
        # xkb — so xkb must stay identity here or letters would double-translate.
        kb_layout = "us,pl";
        kb_options = "grp:alt_caps_toggle,caps:swapescape";
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
        border_size = config.theme.border;
        "col.active_border" = "rgb(${p.mauve}) rgb(${p.teal}) 45deg";
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
        rounding = config.theme.radius;
        active_opacity = 1.0;
        inactive_opacity = 0.96;

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
        enabled = true;

        # Curves: gentle overshoot for opens, snappy decel for closes/moves,
        # linear for the looping border-angle so it never stutters.
        bezier = [
          "overshoot, 0.05, 0.9, 0.1, 1.05"
          "smoothOut, 0.36, 0, 0.66, -0.56"
          "smoothIn, 0.25, 1, 0.5, 1"
          "emphasized, 0.2, 0, 0, 1"
          "linear, 0, 0, 1, 1"
        ];

        animation = [
          # Windows: open with a slight overshoot, close quick, drag smooth.
          "windowsIn, 1, 5, overshoot, slide"
          "windowsOut, 1, 4, smoothOut, slide"
          "windowsMove, 1, 4, emphasized, slide"

          # Fade: short and consistent.
          "fadeIn, 1, 5, smoothIn"
          "fadeOut, 1, 4, smoothOut"
          "fadeSwitch, 1, 4, smoothIn"
          "fadeShadow, 1, 6, smoothIn"
          "fadeDim, 1, 6, smoothIn"

          # Borders: subtle color crossfade only. The gradient-angle rotation
          # (borderangle …, loop) was removed: a looping animation never lets
          # the compositor idle, which defeats `vfr = true` and forces constant
          # GPU repaints/wakeups even on a static screen — wasted battery on a
          # laptop for a barely-visible effect. The active border keeps its
          # static mauve→teal 45° gradient.
          "border, 1, 6, emphasized"

          # Workspaces: slidefade reads as polished and shows direction.
          "workspaces, 1, 5, emphasized, slidefade 15%"
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

          # nixos-assistant: floating Claude Code harness for editing this flake,
          # with a validated rebuild offered on exit. (Replaced the older
          # system-fix binding here; that script stays available as a command.)
          "${mainMod}, grave, exec, nixos-assistant"

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
          # Vicinae — Raycast-style command palette (launch/run/timer/calc).
          "${mainMod}, D, exec, vicinae toggle"
          # Lifelog: focus/launch the viewer on its Search view (MAT-1413).
          "${mainMod} SHIFT, L, exec, lifelog-search"
          "${mainMod}, SLASH, exec, $HOME/Projects/quick-reference-hotkey/quick-ref.sh"
          "${mainMod}, Escape, exec, systemctl suspend"
          "${mainMod}, E, exec, wofi-emoji"
          "${mainMod} SHIFT, Escape, exec, shutdown-script"
          # Quick prediction capture (MAT-1454); displaced `pseudo` (unused)
          "${mainMod}, P, exec, $HOME/Obsidian/Main/scripts/predictions/predict-popup"
          "${mainMod}, S, togglesplit,"
          "${mainMod} SHIFT, B, exec, pkill -SIGUSR1 .waybar-wrapped"
          "${mainMod}, C ,exec, hyprpicker -a"
          "${mainMod}, W,exec, wallpaper-picker"
          "${mainMod} SHIFT, W, exec, vm-start"
          "${mainMod}, B, exec, systemd-run --user --slice=app-zen.slice --scope -- zen-beta"
          "${mainMod}, Y, exec, swaync-client --close-latest"

          "${mainMod} SHIFT, R, exec, notify-send -t 2000 -u normal -i dialog-information \"Starting rebuild 👷!\" \"\" && rebuild && notify-if-command-is-successful rebuild"

          ",XF86AudioLowerVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%-"
          ",XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"

          ", XF86Calculator, exec, speedcrunch"

          # screenshot
          "ALT, Print, exec, ocr-screenshot && wl-paste -t text/plain > ~/Pictures/Screenshots/$(date +'%Y-%m-%d-%Ih%Mm%Ss').txt"
          ",Print, exec, grimblast --notify --freeze copy area && wl-paste -t image/png > ~/Pictures/Screenshots/$(date +'%Y-%m-%d-%Ih%Mm%Ss').png"

          # Power tooling — parallels from Saul's Mac list (MAT-572).
          # clip2md: rich text on the clipboard -> Markdown, in place.
          "${mainMod} SHIFT, M, exec, clip2md"
          # screenshot-search: Alfred's "ss" picker over ~/Pictures/Screenshots.
          "${mainMod} SHIFT, S, exec, screenshot-search"
          # leader: press SUPER+SHIFT+SPACE, release, then a digit -> N-min timer
          # (0 = 10). A general leader submap — see extraConfig below to extend it.
          "${mainMod} SHIFT, Space, submap, leader"

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

          # media controls (volume bound above via wpctl)
          ",XF86AudioMute,exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ",XF86AudioPlay,exec, playerctl play-pause"
          ",XF86AudioNext,exec, playerctl next"
          ",XF86AudioPrev,exec, playerctl previous"
          ",XF86AudioStop, exec, playerctl stop"
          "${mainMod}, mouse_down, workspace, e-1"
          "${mainMod}, mouse_up, workspace, e+1"
          "${mainMod} SHIFT CONTROL, q, exec, reboot"

          # stt-tune cutover (2026-05-10): KP_1/2 → v2 (primary). SHIFT keeps v1
          # as backup so Matt can A/B and roll back without rebuilding.
          ", KP_1, exec, bash /home/matth/Projects/stt-tune/toggle-stt-v2.sh --copy"
          ", KP_End, exec, bash /home/matth/Projects/stt-tune/toggle-stt-v2.sh --copy"
          ", KP_2, exec, bash /home/matth/Projects/stt-tune/toggle-stt-v2.sh --type"
          ", KP_Down, exec, bash /home/matth/Projects/stt-tune/toggle-stt-v2.sh --type"
          # Both Alt keys together = speech-to-text (copy to clipboard). Detected as a
          # kanata CHORD (lalt+ralt → F14 in modules/core/kanata-homerow.nix), NOT a
          # hyprland ALT+Alt bind: hyprland treats both Alts as the same ALT modifier,
          # so the old `ALT, Alt_L`/`ALT, Alt_R` binds wrongly fired on a SINGLE alt
          # press. The chord requires both physical alts. (Needs kanata running.)
          ", F14, exec, bash /home/matth/Projects/stt-tune/toggle-stt-v2.sh --copy"
          # KP_3 (live mode) stays on v1 — v2 doesn't yet implement live streaming
          ", KP_3, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --live"
          # SHIFT modifier = v1 backup (use if v2 misbehaves)
          "SHIFT, KP_1, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --copy"
          "SHIFT, KP_End, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --copy"
          "SHIFT, KP_2, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --type"
          "SHIFT, KP_Down, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --type"
          ", KP_Next, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --live"
          ", KP_4, exec, wl-paste | /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/prompt-llm.py | wl-copy ; notify-send -u normal -i dialog-information 'Copied to clipboard' ''"
          ", KP_Left, exec, wl-paste | /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/prompt-llm.py | wl-copy ; notify-send -u normal -i dialog-information 'Copied to clipboard' ''"
          ", KP_Begin, exec, prompt-picker"
          ", KP_5, exec, prompt-picker"
          ", KP_7, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/open-website-as-standalone-app.sh 'https://gemini.google.com/gem/6dbcf84e326c'"
          ", KP_Home, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/open-website-as-standalone-app.sh 'https://gemini.google.com/gem/6dbcf84e326c'"
          # Polish capture/assist menu (MAT-800): pick a mode, act on the selection/clipboard, route the result
          ", KP_8, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/pl-capture"
          ", KP_Up, exec, bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/pl-capture"

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
          # Paste the 2nd-most-recent clip without reordering cliphist history.
          "CONTROL ALT, V, exec, paste-second-clip"

          # Listen to what you're reading. R resolves the text itself: highlighted
          # text in any app, else a URL in the clipboard, else the focused browser
          # tab (recovered from history — no extension). Playback is one mpv, so
          # SPACE pauses it and ,/. jump back/forward 15s.
          "CONTROL ALT, R, exec, read-aloud"
          "CONTROL ALT, SPACE, exec, read-aloud --toggle"
          "CONTROL ALT, S, exec, read-aloud --stop"
          "CONTROL ALT, comma, exec, read-aloud --seek -15"
          "CONTROL ALT, period, exec, read-aloud --seek 15"
          # NumPad control panel: one key pops a fuzzel menu (pause/stop/seek/
          # speed + read selection/tab/clipboard) — no memorized chords. KP_7 is
          # taken by Gemini; using KP_9 (say the word to move it to KP_7). Both
          # keysyms: KP_9 with NumLock on, KP_Prior with it off.
          ", KP_9, exec, read-aloud --menu"
          ", KP_Prior, exec, read-aloud --menu"
          # Focus/raise the Wispr Flow Hub on its own workspace (see windowrule).
          # W, not I: WhatsApp (wasistlos) gave the key up — see appKeyboardShortcuts.
          "${mainMod} ALT, W, exec, wispr-hub"

          # Tap the copilot key: quick "learn this" launcher — pick a mode,
          # type/paste a word or concept, get an answer instantly in a fresh
          # Claude chat. SUPER+SHIFT opens/focuses the full Claude.ai app, which
          # now lives on its own "claude.ai" workspace (see shared_variables.nix).
          ",${copilotKey}, exec, focus_app claude.ai"
          "SUPER SHIFT, ${copilotKey}, exec, focus_app claude.ai"
          ",XF86Tools, exec, focus_app claude.ai"
          "SUPER SHIFT, XF86Tools, exec, focus_app claude.ai"
          # "SUPER SHIFT, ${copilotKey}, exec, focus_app gemini.google.com"
          # F13 mirrors the laptop's Copilot key so the split keyboards (which
          # have no code:201 hardware key) can reach claude-ask from a layer.
          ",F13, exec, claude-ask"
          "SUPER SHIFT, F13, exec, focus_app claude.ai"

          # clipboard manager
          # Same window footprint, smaller text => more entries visible. Large -preview-width
          # so fuzzel can fuzzy-match text anywhere in an entry, not just the start.
          "${mainMod}, V, exec, cliphist list -preview-width 5000 | fuzzel --dmenu --match-mode=fzf --font=\"${config.theme.font.ui}:size=9\" --line-height=14 --lines=18 --width=70 | cliphist decode | wl-copy"
          "${mainMod} ALT, V, exec, smart-clipboard-picker.sh"
          # link-search: fuzzy-find links (by title or URL) across clipboard + browser history
          "${mainMod} SHIFT, V, exec, link-search"

          # Grammar-check the current selection (fallback: clipboard) with local
          # LanguageTool; issues arrive as a notification. Works in any app —
          # Slack, Obsidian, browser. Script: scripts/grammar-check.sh
          "${mainMod}, C, exec, grammar-check"

          # Password picker (pass + GPG). X types the selected secret into the
          # focused field; SHIFT+X copies it to the clipboard for 45s instead.
          "${mainMod}, X, exec, password-picker"
          "${mainMod} SHIFT, X, exec, password-picker copy"

          "${mainMod} SHIFT, F23, exec, notify-send -t 2000 -u normal -i dialog-information \"Starting rebuild 👷!\" \"\""

          # Translate: SUPER+G enters Dialect submap, SUPER+SHIFT+G enters Crow submap.
          # In submap: letter picks dest language. Bare = current selection, SHIFT = clipboard.
          # Escape exits.
          "${mainMod}, G, submap, translate"
          "${mainMod} SHIFT, G, submap, translate-crow"
        ];

      # mouse binding
      bindm = [
        "${mainMod}, mouse:272, movewindow"
        "${mainMod}, mouse:273, resizewindow"
      ];

      # windowrule
      windowrule =
        generated_singleton_windowrule
        ++ generated_floating_windowrule
        ++ [
          # Wispr Flow ships two windows under one class: "Hub" (the main app) and
          # "Status" (the floating dictation pill). Only the Hub is a singleton on
          # its own workspace — matching on class alone would banish the pill too,
          # and the pill must stay visible on whatever workspace Matt is on.
          "workspace name:wispr, match:class ^(wispr-flow)$, match:title ^(Hub)$"
          "float 0, match:class ^(wispr-flow)$, match:title ^(Hub)$"

          # The pill is always mapped but Wispr parks it on one monitor/workspace,
          # so dictation ran unseen. Pin it (visible on every workspace) and keep
          # it out of the focus/keyboard path; wispr-pill-follow moves it to the
          # cursor when dictation starts.
          "float 1, match:class ^(wispr-flow)$, match:title ^(Status)$"
          "pin 1, match:class ^(wispr-flow)$, match:title ^(Status)$"
          "no_focus 1, match:class ^(wispr-flow)$, match:title ^(Status)$"
          "decorate 0, match:class ^(wispr-flow)$, match:title ^(Status)$"

          # Every espanso (re)start maps a real window — "Espanso Sync Tool", the
          # Wayland sync helper from espanso-detect — which took focus, tiled
          # itself, and reflowed the layout. The espanso-rebind/watchdog units
          # restart espanso on resume, keyboard hotplug and kanata restarts, so
          # this was firing mid-task and yanking focus away.
          #
          # suppress_event is the load-bearing rule, not no_focus: the window
          # *requests activation*, and misc:focus_on_activate=1 hands focus to
          # anything that asks. Verified: without it, focus still moved despite
          # no_focus; with it, focus holds across a restart.
          #
          # It has nothing to show a human, so it also goes to a hidden workspace.
          # CAVEAT: hiding it means it never gets keyboard focus, and espanso
          # 2.3.0's get_modifiers_state() blocks forever waiting for a
          # wl_keyboard.modifiers event that only arrives on focus — so on its
          # own this rule GUARANTEES "espanso running but not expanding". The
          # espanso-wayland overlay patch (modules/core/overlays) gives that
          # loop a 500ms timeout, which is what lets espanso proceed to evdev
          # registration from the hidden workspace. Keep the two together.
          "suppress_event activate activatefocus, match:class ^(Espanso\\.SyncTool)$"
          "no_initial_focus 1, match:class ^(Espanso\\.SyncTool)$"
          "no_focus 1, match:class ^(Espanso\\.SyncTool)$"
          "float 1, match:class ^(Espanso\\.SyncTool)$"
          "no_anim 1, match:class ^(Espanso\\.SyncTool)$"
          "workspace special:hidden silent, match:class ^(Espanso\\.SyncTool)$"

          # Legacy windowrule entries moved to windowrule
          "tile 1, match:class ^(Aseprite)$"
          "float 1, match:title ^(float_kitty)$"
          "center 1, match:title ^(float_kitty)$"
          "size 950 600, match:title ^(float_kitty)$"

          # system-fix Claude session — larger floating window for real work
          "float 1, match:title ^(system-fix)$"
          "center 1, match:title ^(system-fix)$"
          "size 1400 900, match:title ^(system-fix)$"

          # nixos-assistant Claude session — large floating window for real work
          "float 1, match:title ^(nixos-assistant)$"
          "center 1, match:title ^(nixos-assistant)$"
          "size 1400 900, match:title ^(nixos-assistant)$"

          # Zoom's Qt popups (menus, confirm dialogs) close themselves the
          # moment they lose focus, and Hyprland takes focus from them
          # immediately — so they vanish before they can be clicked. Pinning
          # focus on them is the established fix (hyprwm/Hyprland#4809).
          "stay_focused 1, match:class ^(zoom)$, match:title ^(menu window)$"
          "stay_focused 1, match:class ^(zoom)$, match:title ^(confirm window)$"

          "float 1, match:class ^(audacious)$"
          "tile 1, match:class ^(neovide)$"
          # "idleinhibit focus, match:class ^(mpv)$"
          "float 1, match:class ^(udiskie)$"
          "float 1, match:title ^(Transmission)$"
          "float 1, match:title ^(Volume Control)$"
          "float 1, match:title ^(Firefox — Sharing Indicator)$"
          "move 0 0, match:title ^(Firefox — Sharing Indicator)$"
          "size 700 450, match:title ^(Volume Control)$"
          "workspace name:calendar, match:title (calendar)"
          "workspace name:notetaker, match:title (notetaker)"
          "move 40 55%, match:title ^(Volume Control)$"

          # Betterbird: 50% larger than a standard window size
          "size 1800 1000, match:class ^(eu\\.betterbird\\.Betterbird)$"

          # Dialect (translator) — small floating popup
          "float 1, match:class ^(app\\.drey\\.Dialect)$"
          "center 1, match:class ^(app\\.drey\\.Dialect)$"
          "size 720 520, match:class ^(app\\.drey\\.Dialect)$"
          "pin 1, match:class ^(app\\.drey\\.Dialect)$"

          # Crow Translate — small floating popup
          "float 1, match:class ^([Cc]row-?[Tt]ranslate)$"
          "center 1, match:class ^([Cc]row-?[Tt]ranslate)$"
          "size 720 520, match:class ^([Cc]row-?[Tt]ranslate)$"
          "pin 1, match:class ^([Cc]row-?[Tt]ranslate)$"
        ]
        ++ [
          "float 1, match:title ^(Picture-in-Picture)$"
          "opacity 1.0 override 1.0 override, match:title ^(Picture-in-Picture)$"
          "pin 1, match:title ^(Picture-in-Picture)$"
          "opacity 1.0 override 1.0 override, match:title ^(.*swayimg.*)$"
          "opacity 1.0 override 1.0 override, match:title ^(.*mpv.*)$"
          "opacity 1.0 override 1.0 override, match:class (Aseprite)"
          "opacity 1.0 override 1.0 override, match:class (Unity)"
          # "idleinhibit focus, match:class ^(mpv)$"
          # "idleinhibit fullscreen, match:class ^(firefox)$"
          "float 1, match:class ^(zenity)$"
          "center 1, match:class ^(zenity)$"
          "size 850 500, match:class ^(zenity)$"
          "float 1, match:class ^(pwvucontrol)$"
          "float 1, match:class ^(SoundWireServer)$"
          "float 1, match:class ^(.sameboy-wrapped)$"
          "float 1, match:class ^(file_progress)$"
          "float 1, match:class ^(confirm)$"
          "float 1, match:class ^(dialog)$"
          "float 1, match:class ^(download)$"
          "float 1, match:class ^(notification)$"
          "float 1, match:class ^(error)$"
          "float 1, match:class ^(confirmreset)$"
          "float 1, match:title ^(Open File)$"
          "float 1, match:title ^(branchdialog)$"
          "float 1, match:title ^(Confirm to replace files)$"
          "float 1, match:title ^(File Operation Progress)$"

          "opacity 0.0 override, match:class ^(xwaylandvideobridge)$"
          "no_anim 1, match:class ^(xwaylandvideobridge)$"
          "no_initial_focus 1, match:class ^(xwaylandvideobridge)$"
          "max_size 1 1, match:class ^(xwaylandvideobridge)$"
          "no_blur 1, match:class ^(xwaylandvideobridge)$"

          # "workspace, 10, class:^(.*)(discord)(.*)$"
          # "workspace 10, class:^(.*)(discord)(.*)$"
        ];
    };

    extraConfig = "

# Leader submap (MAT-572) — entered via SUPER+SHIFT+SPACE.
# Replicates Saul's sequential-hotkey timer: press the leader, release, then a
# digit to start an N-minute timer (1-9 = 1-9 min, 0 = 10 min). Runs in the
# graphical session, so the start/done desktop notifications fire correctly
# (a kanata system service runs sandboxed and cannot reach the session — see
# MAT-572). This is a GENERAL leader: add more `bind = , <key>, exec, ...` +
# `bind = , <key>, submap, reset` lines below to bind other one-shot actions.
submap = leader
bind = , 1, exec, leader-timer 1
bind = , 1, submap, reset
bind = , 2, exec, leader-timer 2
bind = , 2, submap, reset
bind = , 3, exec, leader-timer 3
bind = , 3, submap, reset
bind = , 4, exec, leader-timer 4
bind = , 4, submap, reset
bind = , 5, exec, leader-timer 5
bind = , 5, submap, reset
bind = , 6, exec, leader-timer 6
bind = , 6, submap, reset
bind = , 7, exec, leader-timer 7
bind = , 7, submap, reset
bind = , 8, exec, leader-timer 8
bind = , 8, submap, reset
bind = , 9, exec, leader-timer 9
bind = , 9, submap, reset
bind = , 0, exec, leader-timer 10
bind = , 0, submap, reset
bind = , escape, submap, reset
submap = reset

# Translate submap — entered via SUPER+G.
# Bare letter = translate current selection. SHIFT+letter = translate clipboard.
# e=English  p=Polish  f=French  s=Spanish  m=Mandarin (zh-CN)  r=Russian
submap = translate
bind = , e, exec, dialect -n -s auto -d en
bind = , e, submap, reset
bind = , p, exec, dialect -n -s auto -d pl
bind = , p, submap, reset
bind = , f, exec, dialect -n -s auto -d fr
bind = , f, submap, reset
bind = , s, exec, dialect -n -s auto -d es
bind = , s, submap, reset
bind = , m, exec, dialect -n -s auto -d zh-CN
bind = , m, submap, reset
bind = , r, exec, dialect -n -s auto -d ru
bind = , r, submap, reset
bind = SHIFT, e, exec, dialect -t \"$(wl-paste)\" -s auto -d en
bind = SHIFT, e, submap, reset
bind = SHIFT, p, exec, dialect -t \"$(wl-paste)\" -s auto -d pl
bind = SHIFT, p, submap, reset
bind = SHIFT, f, exec, dialect -t \"$(wl-paste)\" -s auto -d fr
bind = SHIFT, f, submap, reset
bind = SHIFT, s, exec, dialect -t \"$(wl-paste)\" -s auto -d es
bind = SHIFT, s, submap, reset
bind = SHIFT, m, exec, dialect -t \"$(wl-paste)\" -s auto -d zh-CN
bind = SHIFT, m, submap, reset
bind = SHIFT, r, exec, dialect -t \"$(wl-paste)\" -s auto -d ru
bind = SHIFT, r, submap, reset
bind = , escape, submap, reset
submap = reset

# Translate (Crow Translate) submap — entered via SUPER+SHIFT+G.
# Same key scheme as Dialect submap: letter picks dest language,
# bare = primary selection (wl-paste -p), SHIFT = clipboard (wl-paste).
submap = translate-crow
bind = , e, exec, wl-paste -p | crow --stdin -s auto -t en
bind = , e, submap, reset
bind = , p, exec, wl-paste -p | crow --stdin -s auto -t pl
bind = , p, submap, reset
bind = , f, exec, wl-paste -p | crow --stdin -s auto -t fr
bind = , f, submap, reset
bind = , s, exec, wl-paste -p | crow --stdin -s auto -t es
bind = , s, submap, reset
bind = , m, exec, wl-paste -p | crow --stdin -s auto -t zh-CN
bind = , m, submap, reset
bind = , r, exec, wl-paste -p | crow --stdin -s auto -t ru
bind = , r, submap, reset
bind = SHIFT, e, exec, wl-paste | crow --stdin -s auto -t en
bind = SHIFT, e, submap, reset
bind = SHIFT, p, exec, wl-paste | crow --stdin -s auto -t pl
bind = SHIFT, p, submap, reset
bind = SHIFT, f, exec, wl-paste | crow --stdin -s auto -t fr
bind = SHIFT, f, submap, reset
bind = SHIFT, s, exec, wl-paste | crow --stdin -s auto -t es
bind = SHIFT, s, submap, reset
bind = SHIFT, m, exec, wl-paste | crow --stdin -s auto -t zh-CN
bind = SHIFT, m, submap, reset
bind = SHIFT, r, exec, wl-paste | crow --stdin -s auto -t ru
bind = SHIFT, r, submap, reset
bind = , escape, submap, reset
submap = reset

# # # tablet mode
#       monitor=eDP-1,preferred,0x0,1.0
#       # monitor=DP-1,3840x2400,0x1080,auto, transform, 2
#       monitor=DP-1,preferred,0x1080,1.0

      monitor=eDP-1,preferred,0x0,1.33
      monitor=DP-1,preferred,0x-2160,1 #  monitor above this one
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
    hyprgrass-bind = , edge:l:d, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 4%-

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
