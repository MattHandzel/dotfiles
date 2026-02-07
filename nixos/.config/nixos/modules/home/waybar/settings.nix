{...}: let
  sharedVariables = import ../../../shared_variables.nix;
  singletonIcons = {
    "calendar.google.com" = "📅";
    reclaim = "⏱";
    cura = "🖨";
    obsidian = "🪨";
    slack = "💬";
    btop = "📈";
    notetaker = "📝";
    nautilus = "📁";
    "whatsapp-for-linux" = "🟢";
    "io.github.alainm23.planify" = "✅";
    anki = "🧠";
    planify = "✅";
    PrusaSlicer = "🧩";
    discord = "󰙯";
    thunderbird = "✉";
    gimp = "🎨";
    yazi = "🗂";
    "vit-todo" = "☑";
    "gemini.google.com" = "🧠";
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
      "battery"
      "network"
      "custom/server-status"
      "custom/notification"
    ];
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
              else if name == "calendar.google.com"
              then "🗓️"
              else if name == "whatsapp-for-linux"
              then "whatsapp"
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
