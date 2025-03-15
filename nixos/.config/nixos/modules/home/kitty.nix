{pkgs, ...}: {
  programs.kitty = {
    enable = true;

    themeFile = "Catppuccin-Mocha";

    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };
    settings = {
      confirm_os_window_close = 0;
      background_opacity = "1";
      window_padding_width = 10;
      scrollback_lines = 10000;
      enable_audio_bell = false;
      mouse_hide_wait = 60;

      ## Aesthetics
      # background_image = "/path/to/your/image.png";
      # background_image_layout = "scaled";
      # background_tint = "0.95";
      window_border_width = "1pt";
      active_border_color = "#cba6f7";
      inactive_border_color = "#6c7086";
      cursor_shape = "beam";
      cursor_beam_thickness = "1.5";
      cursor_blink_interval = "0.5";

      ## Tabs
      tab_title_template = "{index}";
      active_tab_font_style = "bold";
      inactive_tab_font_style = "normal";
      tab_bar_style = "powerline";
      tab_powerline_style = "round";
      active_tab_foreground = "#1e1e2e";
      active_tab_background = "#cba6f7";
      inactive_tab_foreground = "#bac2de";
      inactive_tab_background = "#313244";
      tab_bar_min_tabs = 2;
      # tab_bar_edge = "bottom";
      # tab_bar_margin_width = 0.0;
      # tab_bar_margin_height = "0.0 0.0";

      ## URL handling
      url_style = "curly";
      detect_urls = "yes";
      open_url_with = "default";

      ## Visual bell
      visual_bell_duration = "0.1";

      ## Remote control
      allow_remote_control = "yes";
      listen_on = "unix:/tmp/kitty";

      ## Copy/Paste
      copy_on_select = "yes";
      strip_trailing_spaces = "smart";
      paste_actions = "quote-urls-at-prompt";

      ## Layouts
      enabled_layouts = "tall,stack,fat,grid,splits";

      shell = "tmux";
    };

    keybindings = {
      "ctrl+backspace" = "send_text all \\x17";
      "ctrl+shift+backspace" = "send_text all \\x15";
      "ctrl+delete" = "send_text all  \x1b[3;5~";
      # "ctrl+left" = "send_text all \\x01";
      # "ctrl+right" = "send_text all \\x05;

      "ctrl+shift+f" = "kitten hints --type path --program -";
      "ctrl+shift+h" = "kitten hints --type hash --program -";
      "ctrl+shift+p>f" = "kitten hints --type path";
    };
  };
}
