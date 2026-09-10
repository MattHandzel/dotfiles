# JankyBorders — the focused-window outline AeroSpace does not draw.
#
# Mauve #cba6f7 active, surface1 #45475a inactive (theme.nix), 4 pt, round,
# hidpi. Two things start it and must agree: `brew services start borders`
# reads this file, and AeroSpace's after-startup-command (aerospace.nix)
# passes the same options — borders is single-instance, so whichever runs
# second just reconfigures the first.
_: {
  xdg.configFile."borders/bordersrc" = {
    executable = true;
    text = ''
      #!/bin/bash
      # JankyBorders — mauve active border, surface1 inactive (Catppuccin Mocha, theme.nix)
      options=(
        style=round
        width=4.0
        hidpi=on
        active_color=0xffcba6f7
        inactive_color=0xff45475a
      )
      borders "''${options[@]}"
    '';
  };
}
