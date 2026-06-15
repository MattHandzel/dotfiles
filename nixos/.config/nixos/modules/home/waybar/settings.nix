{...}: let
  sharedVariables = import ../../../shared_variables.nix;
  singletonIcons = {
    calendar = "📅";
    cura = "🖨";
    obsidian = "🪨";
    slack = "💬";
    btop = "📈";
    notetaker = "📝";
    nautilus = "📁";
    wasistlos = "🟢";
    "io.github.alainm23.planify" = "✅";
    anki = "🧠";
    planify = "✅";
    PrusaSlicer = "🧩";
    discord = "󰙯";
    thunderbird = "✉";
    gimp = "🎨";
    yazi = "🗂";
    "gemini.google.com" = "🧠";
    "claude.ai" = "🧠";
    beeper = "🔔";
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
      "clock"
    ];
    modules-right = [
      "custom/lifelog"
      "tray"
      "cpu"
      "memory"
      # "disk"
      "pulseaudio"
      "custom/stt-mic"
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
      on-click = "pamixer -t";
    };
    "custom/stt-mic" = {
      interval = 1;
      return-type = "json";
      format = "{}";
      exec = ''bash -lc 'status_file="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/stt-waybar-status.json"; if [[ -s "$status_file" ]]; then cat "$status_file"; else printf "%s\n" "{\"text\":\"\",\"class\":[\"off\"],\"tooltip\":\"STT off (click to toggle live)\"}"; fi' '';
      on-click = "bash /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/toggle-stt.sh --live";
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
