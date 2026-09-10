{...}: let
  sharedVariables = import ../../../shared_variables.nix;
  singletonIcons = {
    calendar = "📅";
    cura = "🖨";
    obsidian = "🪨";
    slack = "🕴️";
    btop = "📈";
    notetaker = "📔";
    dolphin = "📁";
    wasistlos = "🟢";
    "io.github.alainm23.planify" = "✅";
    anki = "🧠";
    tasker = "📝";
    planify = "✅";
    PrusaSlicer = "🧩";
    discord = "󰙯";
    superhuman = "✉️";
    gimp = "🎨";
    yazi = "🗂";
    "gemini.google.com" = "🧠";
    "claude.ai" = "🧠";
    "com.anthropic.Claude" = "✳️";
    beeper = "🔔";
    linear = "📐";
    spotify = "";
  };
in {
  programs.waybar.settings.mainBar = {
    position = "bottom";
    layer = "top";
    height = 5;
    margin-top = 0;
    margin-bottom = 0;
    margin-left = 0;
    margin-right = 0;
    modules-left = [
      "custom/launcher"
      "hyprland/workspaces"
    ];
    modules-center = [
      "custom/agenda"
      "clock"
    ];
    modules-right = [
      "custom/writing"
      "custom/lifelog"
      "tray"
      "cpu"
      "memory"
      # "disk"
      "pulseaudio"
      "custom/kb-lang"
      "custom/stt-mic"
      "custom/wispr"
      "custom/focus-mode"
      "battery"
      "network"
      "custom/server-status"
      "custom/notification"
    ];
    "custom/focus-mode" = {
      interval = 5;
      return-type = "json";
      exec = "toggle-focus-mode --status";
      on-click = "toggle-focus-mode";
      tooltip = true;
    };
    # "now / next" calendar slot, immediately left of the clock. Polls every 30s so
    # the countdown ticks; the underlying agenda cache is refreshed out-of-band by
    # calendar-agenda.timer (modules/core/calendar-agenda.nix), so this does no
    # network I/O. Click opens the existing Google Calendar app window.
    "custom/agenda" = {
      interval = 30;
      return-type = "json";
      exec = "waybar-agenda";
      exec-if = "command -v waybar-agenda";
      on-click = "calendar";
      tooltip = true;
      max-length = 64;
    };
    clock = {
      calendar = {
        format = {today = "<span color='#b4befe'><b><u>{}</u></b></span>";};
      };
      format = " {:%Y-%m-%d %H:%M}";
      tooltip = "true";
      tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      format-alt = " {:%Y-%m-%d %H:%M}";
    };
    "custom/server-status" = {
      interval = 15;
      return-type = "json";
      exec-if = "command -v server-status";
      exec = "server-status";
    };
    "hyprland/workspaces" = {
      active-only = false;
      disable-scroll = true;
      format = "{icon}";
      on-click = "activate";
      sort-by-number = true;
      format-icons =
        {
          "1" = "󰈹";
          "11" = "󰈹";
          "2" = "";
          "12" = "";
          # "3"= "󰘙";
          # "4"= "󰙯";
          # "5"= "";
          # "6"= "";
          "10.5" = "|";
          "spotify" = "";
          urgent = "";
          # default = "";
        }
        // (builtins.listToAttrs (map (name: {
            name =
              if name == "thunderbird"
              then "8"
              else if name == "discord"
              then "10"
              else if name == "calendar"
              then "calendar"
              else if name == "wasistlos"
              then "wasistlos"
              # workspaceMapping sends the Claude Desktop app to the "claude"
              # workspace; key the icon by that name so waybar matches it.
              else if name == "com.anthropic.Claude"
              then "claude"
              else name;
            value = singletonIcons.${name};
          })
          sharedVariables.singletonApplications));
      persistent-workspaces = {
        # "1"= [];
        # "2"= [];
        # "3"= [];
        # "4"= [];
        # "5"= [];
        "10.5" = [];
      };
    };
    "custom/writing" = {
      # Drafting speed for the current writing session (Chapin: clear 500
      # words/hour and you outrun the inner critic). The module is empty
      # whenever no session is running, so it costs no bar space when idle.
      #
      # This poll is also what SAMPLES the session — `status` folds the current
      # word count into the running average as a side effect, which is why
      # there is no daemon. 5s keeps the readout live while typing without
      # making the average jumpy.
      interval = 5;
      return-type = "json";
      format = "{}";
      exec = "writing-session status --json";
      on-click = "writing-session stop";
      tooltip = true;
    };
    "custom/lifelog" = {
      "exec" = "cat /tmp/lifelog_status.json";
      "interval" = 5;
      "return-type" = "json";
      "format" = "{}";
      "on-click" = "kitty -e nix-shell /home/matth/Projects/LifeLogging/shell.nix --run 'python3 /home/matth/Projects/LifeLogging/run.py tui'";
    };

    memory = {
      format = "󰟜 {}%";
      format-alt = "󰟜 {used} GiB"; # 
      interval = 10;
    };
    cpu = {
      format = "  {usage}%";
      format-alt = "  {avg_frequency} GHz";
      interval = 10;
    };
    disk = {
      # path = "/";
      format = "󰋊 {percentage_used}%";
      interval = 300;
    };
    network = {
      format-wifi = "  {signalStrength}%";
      format-ethernet = "󰀂 ";
      tooltip-format = "Connected to {essid} {ifname} via {gwaddr}";
      format-linked = "{ifname} (No IP)";
      format-disconnected = "󰖪 ";
    };
    tray = {
      icon-size = 20;
      spacing = 8;
    };
    pulseaudio = {
      format = "{icon} {volume}%";
      format-muted = "  {volume}%";
      format-icons = {
        default = [" "];
      };
      scroll-step = 5;
      on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
    };
    "custom/stt-mic" = {
      # Was interval=1 with `bash -lc` — a full *login* shell spawned every
      # second just to cat a status file. interval=3 + `bash -c` (no profile
      # sourcing) cuts that idle churn ~3x with no visible change.
      interval = 3;
      return-type = "json";
      format = "{}";
      exec = ''bash -c 'status_file="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/stt-waybar-status.json"; if [[ -s "$status_file" ]]; then cat "$status_file"; else printf "%s\n" "{\"text\":\"\",\"class\":[\"off\"],\"tooltip\":\"STT off (click to toggle live)\"}"; fi' '';
      on-click = "bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --live";
      tooltip = true;
    };
    "custom/wispr" = {
      # Live mic-level meter for Wispr Flow. Streams JSON continuously (no
      # interval): off/idle/listening/silent. `silent` = REC is live but the
      # mic is ~silent (muted / wrong default source) — the failure that used
      # to look identical to a good dictation. Click focuses the Hub.
      return-type = "json";
      format = "{}";
      exec = "wispr-meter";
      restart-interval = 2;
      on-click = "wispr-hub";
      tooltip = true;
    };
    "custom/kb-lang" = {
      # Polls the main Hyprland keyboard's active layout (flag + class).
      # Click cycles to the next layout via `kb-lang-status toggle` (the
      # existing `grp:alt_caps_toggle` key combo still works alongside).
      # signal=8 lets the toggle path send RTMIN+8 for instant refresh.
      interval = 2;
      return-type = "json";
      format = "{}";
      exec = "kb-lang-status";
      on-click = "kb-lang-status toggle";
      signal = 8;
      tooltip = true;
    };
    battery = {
      format = "{icon} {capacity}%";
      format-icons = [" " " " " " " " " "];
      format-charging = " {capacity}%";
      format-full = " {capacity}%";
      format-warning = " {capacity}%";
      interval = 20;
      states = {
        warning = 20;
      };
      format-time = "{H}h{M}m";
      tooltip = true;
      tooltip-format = "{time}";
    };
    "custom/launcher" = {
      format = "";
      on-click = "fuzzel";
      on-click-right = "wallpaper-picker";
      tooltip = "false";
    };
    "custom/notification" = {
      tooltip = false;
      format = "{icon} ";
      format-icons = {
        notification = "<span foreground='red'><sup></sup></span>   ";
        none = "   ";
        dnd-notification = "<span foreground='red'><sup></sup></span>   ";
        dnd-none = "   ";
        inhibited-notification = "<span foreground='red'><sup></sup></span>   ";
        inhibited-none = "   ";
        dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>   ";
        dnd-inhibited-none = "   ";
      };
      return-type = "json";
      exec-if = "which swaync-client";
      exec = "swaync-client -swb";
      on-click = "swaync-client -t -sw";
      on-click-right = "swaync-client -d -sw";
      escape = true;
    };
  };
}
