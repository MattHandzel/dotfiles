{...}: let
  custom = {
    font = "JetBrainsMono Nerd Font";
    font_size = "15px";
    font_weight = "bold";
    text_color = "#cdd6f4";
    secondary_accent = "89b4fa";
    tertiary_accent = "f5f5f5";
    background = "11111B";
    opacity = "0.98";
  };
in {
  programs.waybar.style = ''

    * {
        border: none;
        border-radius: 0px;
        padding: 0;
        margin: 0;
        min-height: 0px;
        font-family: ${custom.font};
        font-weight: ${custom.font_weight};
        opacity: ${custom.opacity};
    }

    window#waybar {
        background: none;
    }

    #workspaces {
        font-size: 18px;
        padding-left: 15px;

    }
    #workspaces button {
        color: ${custom.text_color};
        padding-left:  6px;
        padding-right: 6px;
    }
    #workspaces button.empty {
        color: #6c7086;
    }
    #workspaces button.active {
        color: #b4befe;
    }

    #tray, #pulseaudio, #network, #cpu, #memory, #disk, #clock, #battery, #custom-notification, #custom-stt-mic {
        font-size: ${custom.font_size};
        color: ${custom.text_color};
    }

    #cpu {
        padding-left: 15px;
        padding-right: 9px;
        margin-left: 7px;
    }
    #memory {
        padding-left: 9px;
        padding-right: 9px;
    }
    #disk {
        padding-left: 9px;
        padding-right: 15px;
    }

    #tray {
        padding: 0 20px;
        margin-left: 7px;
    }

    #pulseaudio {
        padding-left: 15px;
        padding-right: 9px;
        margin-left: 7px;
    }
    #battery {
        padding-left: 9px;
        padding-right: 9px;
    }
    #custom-stt-mic {
        padding-left: 9px;
        padding-right: 9px;
    }
    #custom-stt-mic.off {
        color: rgba(205, 214, 244, 0.4);
    }
    #custom-stt-mic.active {
        color: ${custom.text_color};
    }
    #custom-stt-mic.speaking {
        color: #a6e3a1;
    }
    #custom-focus-mode {
        padding-left: 9px;
        padding-right: 9px;
    }
    #custom-focus-mode.off {
        color: rgba(205, 214, 244, 0.4);
    }
    #custom-focus-mode.on {
        color: #fab387; /* Peach/Orange */
        font-size: 18px;
        /* Subtle pulse effect for active focus mode */
        animation-name: blink;
        animation-duration: 2s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
    }
    #network {
        padding-left: 9px;
        padding-right: 30px;
    }

    custom-notification {
        padding-left: 20px;
        padding-right: 20px;
    }

    #clock {
        padding-left: 9px;
        padding-right: 15px;
    }

    #custom-launcher {
        font-size: 20px;
        color: #b4befe;
        font-weight: ${custom.font_weight};
        padding-left: 10px;
        padding-right: 15px;
    }

    #custom-lifelog.running {
       color: #a6e3a1; /* Green */
    }
    #custom-lifelog.stopped {
       color: #f38ba8; /* Red */
    }
    #custom-lifelog.warning {
       color: #f9e2af; /* Yellow/Orange - for partial failures */
    }

    @keyframes blink {
        to {
            color: #f38ba8; /* Red */
        }
    }
  '';
}
