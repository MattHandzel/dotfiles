{config, ...}: let
  p = config.theme.palette;
  font = config.theme.font;
  custom = {
    font = font.mono;
    font_size = "${toString font.sizes.lg}px";
    font_weight = "bold";
    text_color = "#${p.text}";
    opacity = toString config.theme.opacity;
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
        font-size: ${toString font.sizes.xl}px;
        padding-left: 15px;

    }
    #workspaces button {
        color: ${custom.text_color};
        padding-left:  6px;
        padding-right: 6px;
    }
    #workspaces button.empty {
        color: #${p.overlay0};
    }
    #workspaces button.active {
        color: #${p.lavender};
    }

    #tray, #pulseaudio, #network, #cpu, #memory, #disk, #clock, #battery, #custom-notification, #custom-stt-mic, #custom-kb-lang {
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
        color: #${p.green};
    }
    #custom-kb-lang {
        padding-left: 9px;
        padding-right: 9px;
    }
    #custom-kb-lang.pl {
        color: #${p.red};
    }
    #custom-kb-lang.en {
        color: #${p.blue};
    }
    #custom-kb-lang.unknown,
    #custom-kb-lang.other {
        color: rgba(205, 214, 244, 0.6);
    }
    #custom-focus-mode {
        padding-left: 9px;
        padding-right: 9px;
    }
    #custom-focus-mode.off {
        color: rgba(205, 214, 244, 0.4);
    }
    #custom-focus-mode.on {
        color: #${p.peach};
        font-size: ${toString font.sizes.xl}px;
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
        font-size: ${toString font.sizes.xl}px;
        color: #${p.lavender};
        font-weight: ${custom.font_weight};
        padding-left: 10px;
        padding-right: 15px;
    }

    #custom-lifelog.running {
       color: #${p.green};
    }
    #custom-lifelog.stopped {
       color: #${p.red};
    }
    #custom-lifelog.warning {
       color: #${p.yellow};
    }

    @keyframes blink {
        to {
            color: #${p.red};
        }
    }
  '';
}
