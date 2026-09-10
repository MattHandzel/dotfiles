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
    #custom-writing {
        padding-left: 9px;
        padding-right: 9px;
    }
    /* Under Chapin's 500 words/hour floor — the state worth noticing, so it is
       the only one that gets a warm colour. Green once you clear the bar. */
    #custom-writing.under-target {
        color: #${p.peach};
    }
    #custom-writing.on-target {
        color: #${p.green};
    }
    /* First 30s: too little signal to show a rate. */
    #custom-writing.warming {
        color: rgba(205, 214, 244, 0.4);
    }
    #custom-wispr {
        font-size: ${custom.font_size};
        padding-left: 9px;
        padding-right: 9px;
    }
    #custom-wispr.idle {
        color: #${p.mauve};
    }
    #custom-wispr.listening {
        color: #${p.green};
    }
    #custom-wispr.silent {
        color: #${p.base};
        background-color: #${p.red};
        border-radius: 8px;
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
    /* now/next calendar slot, left of the clock. Colour encodes urgency so the
       state is readable without parsing the text. */
    #custom-agenda {
        padding-left: 9px;
        padding-right: 9px;
        color: #${p.text};
    }
    #custom-agenda.free {
        color: rgba(205, 214, 244, 0.4);
    }
    #custom-agenda.soon {
        color: #${p.yellow};
    }
    #custom-agenda.imminent {
        color: #${p.peach};
        animation-name: blink;
        animation-duration: 2s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
    }
    #custom-agenda.conflict {
        color: #${p.red};
    }
    /* the fetcher stopped updating — surface it rather than showing stale times */
    #custom-agenda.stale, #custom-agenda.error {
        color: #${p.overlay0};
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
