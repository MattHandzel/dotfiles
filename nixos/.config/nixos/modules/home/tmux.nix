{
  config,
  pkgs,
  ...
}: let
  inherit (pkgs) tmuxPlugins;
in {
  programs.tmux = {
    enable = true;
    package = pkgs.tmux;
    baseIndex = 0;
    historyLimit = 100000;
    keyMode = "vi";
    mouse = true;
    terminal = "tmux-256color";
    shell = "/run/current-system/sw/bin/zsh";
    prefix = "C-Space";
    extraConfig = ''
        set-option -sa terminal-overrides ",xterm*:Tc"

        unbind C-b
        bind-key C-Space send-prefix

        unbind %
        bind | split-window -h -c "#{pane_current_path}"

        unbind '"'
        bind - split-window -v -c "#{pane_current_path}"

        bind r source-file ~/.config/tmux/tmux.conf
        unbind r

        set -g status-position top
        bind-key h select-pane -L
        bind-key j select-pane -D
        bind-key k select-pane -U
        bind-key l select-pane -R

        bind-key -n M-Left previous-window
        bind-key -n M-Right next-window

        bind -n S-Left resize-pane -L 2
        bind -n S-Right resize-pane -R 2
        bind -n S-Up resize-pane -U 2
        bind -n S-Down resize-pane -D 2

        bind-key -n '^H' send-keys C-w

        # Smart pane switching with Vim
        # is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"
        # bind-key -n 'C-h' if-shell "$is_vim" 'send-keys C-h' 'select-pane -L'
        # bind-key -n 'C-j' if-shell "$is_vim" 'send-keys C-j' 'select-pane -D'
        # bind-key -n 'C-k' if-shell "$is_vim" 'send-keys C-k' 'select-pane -U'
        # bind-key -n 'C-l' if-shell "$is_vim" 'send-keys C-l' 'select-pane -R'
      bind -n C-h if -F '#{m:#{pane_current_command},(^|/|g)?(view|l?n?vim?x?|fzf)(diff)?$}' 'send-keys C-h' 'select-pane -L'
      bind -n C-j if -F '#{m:#{pane_current_command},(^|/|g)?(view|l?n?vim?x?|fzf)(diff)?$}' 'send-keys C-j' 'select-pane -D'
      bind -n C-k if -F '#{m:#{pane_current_command},(^|/|g)?(view|l?n?vim?x?|fzf)(diff)?$}' 'send-keys C-k' 'select-pane -U'
      bind -n C-l if -F '#{m:#{pane_current_command},(^|/|g)?(view|l?n?vim?x?|fzf)(diff)?$}' 'send-keys C-l' 'select-pane -R'

        set -sg escape-time 10
        set -g renumber-windows on
        set -g set-clipboard on
        setw -g mode-keys vi
        set -g pane-active-border-style 'fg=magenta,bg=default'
        set -g pane-border-style 'fg=brightblack,bg=default'

        bind-key -n M-n new-window  "tmux-sessionizer"
        # bind-key -n M-Tab switch-client -1
        bind C-t choose-tree
        set-option -g automatic-rename on
        set-option -g automatic-rename-format '#{b:pane_current_path}'

        set -g @thumbs-command 'echo -n {} | wl-copy'
        set -g @thumbs-alphabet dvorak-homerow
        set -g @thumbs-reverse enabled
        # set -g @thumbs-regexp-1 '[\w-\.]+@([\w-]+\.)+[\w-]{2,4}' # Match emails
        # set -g @thumbs-regexp-2 '[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:' # Match MAC addresses
        set -g @plugin 'akohlbecker/aw-watcher-tmux'
        set -g @plugin 'christoomey/vim-tmux-navigator'
        set -ga update-environment TERM
        set -ga update-environment TERM_PROGRAM

        set -gq allow-passthrough on
        set -g visual-activity off

        # set -g @thumbs-upcase-command 'tmux set-buffer -- {} && tmux paste-buffer | wl-copy'

        # Plugins
        run '~/.tmux/plugins/tpm/tpm'
    '';

    plugins = with tmuxPlugins; [
      sensible
      better-mouse-mode
      fuzzback
      yank
      prefix-highlight
      {
        plugin = tmux-thumbs;
        extraConfig = "set -g @thumbs-command 'fzf --reverse'";
      }
      {
        plugin = tmux-fzf;
        extraConfig = "set -g @fzf-command 'fzf --reverse'";
      }
      {
        plugin = fzf-tmux-url;
        extraConfig = "set -g @fzf-url-command 'fzf --reverse'";
      }
      {
        plugin = catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavour 'mocha'
          set -g @catppuccin_window_left_separator ""
          set -g @catppuccin_window_right_separator " "
          set -g @catppuccin_status_right_separator " "
          set -g @catppuccin_meetings_text "#($HOME/.config/tmux/scripts/cal.sh)"
        '';
      }
    ];
  };
}
