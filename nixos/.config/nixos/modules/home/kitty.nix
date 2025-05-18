{pkgs, ...}: {
  programs.kitty = {
    enable = true;

    font = {
      name = "JetBrainsMono Nerd Font";
      package = pkgs.nerdfonts.override {fonts = ["JetBrainsMono"];};
      size = 10;
    };

    settings = {
      confirm_os_window_close = 0;
      dynamic_background_opacity = "no";
      window_padding_width = 10;
      scrollback_lines = 20000;
      enable_audio_bell = false;
      mouse_hide_wait = 60;

      ## Performance improvements
      repaint_delay = 10;
      input_delay = 3;
      sync_to_monitor = false;

      ## Advanced cursor customization
      cursor_shape = "beam";
      cursor_beam_thickness = "1.5";
      cursor_blink_interval = 0.5;
      cursor_stop_blinking_after = 15.0;

      ## URL handling improvements
      url_style = "double";
      show_hyperlink_targets = "yes";
      underline_hyperlinks = "always";
      detect_urls = "yes";

      ## Tab improvements
      # Use tmux instead
      # tab_title_template = "{title}{' :{}:'.format(num_windows) if num_windows > 1 else ''}";
      # active_tab_font_style = "bold-italic";
      # inactive_tab_font_style = "normal";
      # tab_bar_style = "powerline";
      # tab_powerline_style = "slanted";
      # active_tab_foreground = "#1e1e2e";
      # active_tab_background = "#cba6f7";
      # inactive_tab_foreground = "#bac2de";
      # inactive_tab_background = "#313244";
      # tab_bar_min_tabs = 1;
      # tab_bar_edge = "bottom";
      # tab_bar_margin_width = 0.0;
      # tab_bar_margin_height = "0.0 0.0";

      ## Window layout
      enabled_layouts = "tall,stack,fat,grid,splits";
      remember_window_size = "yes";
      initial_window_width = 1200;
      initial_window_height = 768;

      ## Advanced copy/paste
      copy_on_select = "yes";
      strip_trailing_spaces = "smart";
      paste_actions = "quote-urls-at-prompt";
      clipboard_control = "write-clipboard write-primary read-clipboard read-primary";

      ## Terminal features
      term = "xterm-256color";
      shell_integration = "enabled";
      allow_hyperlinks = "yes";
    };

    keybindings = {
      # Improved navigation
      "ctrl+left" = "send_text all \\x1b[1;5D";
      "ctrl+right" = "send_text all \\x1b[1;5C";
      "ctrl+backspace" = "send_text all \\x17";
      "ctrl+shift+backspace" = "send_text all \\x15";

      # Tab management
      "ctrl+shift+t" = "new_tab";
      "ctrl+shift+w" = "close_tab";
      "ctrl+tab" = "next_tab";
      "ctrl+shift+tab" = "previous_tab";

      # Window management
      "ctrl+shift+enter" = "new_window";
      "ctrl+shift+]" = "next_window";
      "ctrl+shift+[" = "previous_window";

      # Advanced hints
      "ctrl+shift+f" = "kitten hints --type path --program -";
      "ctrl+shift+h" = "kitten hints --type hash --program -";
      "ctrl+shift+p>f" = "kitten hints --type path";
      "ctrl+shift+e" = "kitten hints --type line";

      # Layout management
      "ctrl+shift+l" = "next_layout";

      # Scrolling
      "ctrl+shift+up" = "scroll_line_up";
      "ctrl+shift+down" = "scroll_line_down";
      "shift+page_up" = "scroll_page_up";
      "shift+page_down" = "scroll_page_down";

      # Miscellaneous
      "ctrl+shift+equal" = "increase_font_size";
      "ctrl+shift+minus" = "decrease_font_size";
    };
  };
}
