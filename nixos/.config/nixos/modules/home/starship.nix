{
  lib,
  inputs,
  config,
  ...
}: let
  p = config.theme.palette;
in {
  programs.starship = {
    enable = true;

    enableBashIntegration = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;

    settings = {
      # right_format = "$cmd_duration";

      directory = {
        format = "[ ](bold #${p.blue})[ $path ]($style)";
        style = "bold #${p.lavender}";
      };

      character = {
        success_symbol = "[ ](bold #${p.blue})[ ➜](bold green)";
        error_symbol = "[ ](bold #${p.blue})[ ➜](bold red)";
      };

      cmd_duration = {
        format = "[󰔛 $duration]($style)";
        disabled = false;
        style = "bg:none fg:#${p.yellow}";
        show_notifications = false;
        min_time_to_notify = 60000;
      };
      palette = "catppuccin_mocha";
    };
  };
}
