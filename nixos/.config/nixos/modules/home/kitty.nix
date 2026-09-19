{
  lib,
  pkgs,
  ...
}: {
  programs.kitty = {
    enable = true;

    font = {
      name = "JetBrainsMono Nerd Font";
      package = pkgs.nerd-fonts.jetbrains-mono;
      size = 13;
    };

    settings =
      {
        confirm_os_window_close = 0;
        # No macOS title bar. AeroSpace tiles these windows, so the chrome strip
        # only wasted a row and put a close button where a mis-click lands.
        hide_window_decorations = "titlebar-only";
        dynamic_background_opacity = "no";
        # 6, not 10: with gaps 0 the tile edge is the frame, and 10 read as a gap.
        window_padding_width = 6;
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
        cursor_blink_interval = 0; # a beam that holds still
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
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        # Without this, macOS sends Option as a compose/dead key and tmux/nvim
        # never see M-n, M-Left, M-Right — the bindings tmux.nix defines.
        macos_option_as_alt = "yes";
        # Remote control, socket-only (no TTY escape-sequence control), so the
        # Oops incident capture can read the focused window's screen and last
        # command output (`kitty @ --to unix:/tmp/kitty-<pid> get-text`). One
        # socket per kitty instance; `open -na kitty` spawns several. 2026-09-12.
        allow_remote_control = "socket-only";
        listen_on = "unix:/tmp/kitty"; # kitty appends -<pid> itself -> /tmp/kitty-<pid>
        # AeroSpace owns window placement; kitty must not also restore its own.
        macos_quit_when_last_window_closed = "yes";
        # The laptop ran kitty at 0.80 through a Hyprland window rule. macOS has
        # no compositor rule, so kitty does it itself: 0.94 with the system blur
        # behind it keeps text crisp on a busy wallpaper and still lets the
        # Mocha ground breathe.
        background_opacity = "0.94";
        background_blur = 20;
      };

    keybindings = {
      # Improved navigation
      "ctrl+left" = "send_text all \\x1b[1;5D";
      "ctrl+right" = "send_text all \\x1b[1;5C";
      # macOS-standard line editing. kitty maps neither by default, so
      # cmd+backspace did nothing and the muscle memory landed on
      # ctrl+backspace below, which is word-delete.
      "cmd+backspace" = "send_text all \\x17";   # delete previous WORD
      "cmd+delete" = "send_text all \\x17";
      "ctrl+backspace" = "send_text all \\x17";

      # Command-as-Control, done in kitty rather than in Karabiner.
      #
      # karabiner.nix has a cmdIsCtrlInKitty rule, but Karabiner never grabs the
      # Totem and Matt does not want it to (2026-09-12), so that rule reaches the
      # BUILT-IN keyboard only. These maps are keyboard-agnostic: kitty sees
      # cmd+<key> from any board and emits the control byte itself. On the
      # internal keyboard Karabiner has already turned Command into Control, so
      # kitty receives ctrl+<key> and these never fire. Both paths converge on
      # the same byte, so the two keyboards behave identically.
      #
      # DELIBERATELY NOT MAPPED, because each would cost a chord worth more than
      # it gains:
      #   cmd+q          quit, and cmd+space is eaten by Spotlight before kitty
      #   cmd+t / cmd+n  new tab and new window
      # Clipboard, moved to the Linux terminal convention (2026-09-12).
      #
      # On Linux a terminal copies with Ctrl+Shift+C and pastes with
      # Ctrl+Shift+V, precisely so that plain Ctrl+C stays SIGINT and plain
      # Ctrl+V stays the literal-insert. macOS instead puts copy/paste on
      # cmd+C/cmd+V, which is what made Command-as-Control lossy here: there is
      # no right-Command escape hatch inside kitty.
      #
      # Shifting the clipboard onto the SHIFT variants resolves it. Command is
      # now Control for every letter, including C and V, and the clipboard lives
      # exactly where it does on Linux.
      #
      # Both spellings are mapped on purpose. On the Totem, Command reaches kitty
      # untouched and cmd+shift+c arrives. On the built-in keyboard Karabiner has
      # already rewritten Command to Control, so the same thumb produces
      # ctrl+shift+c. Mapping both makes the two keyboards behave identically.
      "cmd+c" = "send_text all \\x03";   # C-c  SIGINT, NOT copy
      "cmd+v" = "send_text all \\x16";   # C-v  literal insert, NOT paste
      "cmd+shift+c" = "copy_to_clipboard";
      "cmd+shift+v" = "paste_from_clipboard";
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";

      "cmd+space" = "send_text all \\x00";   # C-Space, the tmux prefix (see tmux.conf: set -g prefix C-Space)
      "cmd+h" = "send_text all \\x08";   # C-h  pane left  (TmuxNavigateLeft)
      "cmd+j" = "send_text all \\x0a";   # C-j  pane down  (TmuxNavigateDown)
      "cmd+k" = "send_text all \\x0b";   # C-k  pane up    (TmuxNavigateUp)
      "cmd+l" = "send_text all \\x0c";   # C-l  pane right (TmuxNavigateRight)
      "cmd+w" = "send_text all \\x17";   # C-w  nvim window prefix; overrides kitty close-window
      "cmd+d" = "send_text all \\x04";   # C-d  half page down
      "cmd+u" = "send_text all \\x15";   # C-u  half page up
      "cmd+r" = "send_text all \\x12";   # C-r  redo / reverse search
      "cmd+o" = "send_text all \\x0f";   # C-o  jump back
      "cmd+i" = "send_text all \\x09";   # C-i  jump forward (Tab)
      # C-s. nvim maps <C-s> to "<cmd>w<cr><esc>" for i/x/n/s (mappings.lua), so
      # this is Save. Unmapped, cmd+s hit kitty's own "Secure Keyboard Entry" menu
      # item instead and silently toggled it — see NSUserKeyEquivalents in
      # modules/darwin/system-defaults.nix, which parks that item off cmd+s.
      # \x13 is also XOFF, so zsh.nix runs `stty -ixon` to stop it freezing a
      # plain shell; nvim reads the raw byte and is unaffected either way.
      "cmd+s" = "send_text all \\x13";
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
    }
    // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      # Matt's Mac font-size keys, in every kitty window (nvim's <C-Up>/<C-Down>
      # window resize is shadowed there). Needs macOS's Ctrl+Up/Down Mission
      # Control hotkeys off (modules/darwin/system-defaults.nix). 2026-09-14.
      "ctrl+up" = "change_font_size all +1.0";
      "ctrl+down" = "change_font_size all -1.0";
    };
  };
}
