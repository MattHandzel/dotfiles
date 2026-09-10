{config, ...}: let
  p = config.theme.palette;
  font = config.theme.font;
in {
  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "${font.ui}:weight=bold:size=${toString font.sizes.sm}";
        line-height = 20;
        fields = "name,generic,comment,categories,filename,keywords";
        terminal = "kitty";
        prompt = "' ➜  '";
        icon-theme = "Papirus-Dark";
        layer = "top";
        lines = 10;
        width = 30;
        horizontal-pad = 25;
        inner-pad = 5;
      };
      colors = {
        background = "${p.base}cc";
        text = "${p.text}ff";
        match = "${p.red}ff";
        selection = "${p.lavender}aa";
        selection-match = "${p.red}ff";
        selection-text = "${p.text}ff";
        border = "${p.lavender}ff";
      };
      border = {
        radius = 15;
        width = 3;
      };
    };
  };
}
