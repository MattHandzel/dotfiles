{
  pkgs,
  config,
  ...
}: let
  p = config.theme.palette;
  font = config.theme.font;
in {
  home.packages = [pkgs.hyprlock];
  xdg.configFile."hypr/hyprlock.conf".text = ''
    $red = rgb(${p.red})
    $yellow = rgb(${p.yellow})
    $lavender = rgb(${p.lavender})

    $mauve = rgb(${p.mauve})
    $mauveAlpha = ${p.mauve}

    $base = rgb(${p.base})
    $surface0 = rgb(${p.surface0})
    $text = rgb(${p.text})
    $textAlpha = ${p.text}

    $accent = $lavender
    $accentAlpha = $mauveAlpha
    $font = ${font.mono}

    # GENERAL
    general {
      disable_loading_bar = true
      hide_cursor = true
    }

    # BACKGROUND
    background {
      monitor =
      path = ~/Pictures/wallpapers/others/purplesky.png
      color = $base
      blur_passes = 0
    }

    # TIME
    label {
      monitor =
      text = cmd[update:30000] echo "<b><big> $(date +"%R") </big></b>"
      color = $text
      font_size = ${toString font.sizes.huge}
      font_family = $font
      shadow_passes = 3
      shadow_size = 3

      position = 0, -100
      halign = center
      valign = top
    }

    # DATE
    label {
      monitor =
      text = cmd[update:43200000] echo "$(date +"%A, %d %B %Y")"
      color = $text
      font_size = ${toString font.sizes.xl}
      font_family = $font
      position = 0, -300
      halign = center
      valign = top
    }

    # USER AVATAR

    image {
      monitor =
      path = ~/Pictures/pp/pp.png
      size = 125
      border_color = $accent

      position = 0, -450
      halign = center
      valign = center
    }

    # INPUT FIELD
    input-field {
      monitor =
      size = 300, 60
      outline_thickness = 4
      dots_size = 0.2
      dots_spacing = 0.4
      dots_center = true
      outer_color = $accent
      inner_color = $surface0
      font_color = $text
      fade_on_empty = false
      placeholder_text = <span foreground="##$textAlpha"><i>󰌾  Logged in as </i><span foreground="##$accentAlpha">$USER</span></span>
      hide_input = false
      check_color = $accent
      fail_color = $red
      fail_text = <i>$FAIL <b>($ATTEMPTS)</b></i>
      capslock_color = $yellow
      position = 0, -100
      halign = center
      valign = center
    }
  '';
}
