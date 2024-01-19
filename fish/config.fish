if status is-interactive
    # Commands to run in interactive sessions can go here
    alias slack 'bash /home/matthandzel/.local/share/flatpak/app/com.slack.Slack/current/active/export/bin/com.slack.Slack'
    alias clipboard="xclip -selection clipboard"
    alias gitca="git commit -a -m"
    alias n="nvim"
    # Set the default editor
    export EDITOR=nvim

    # Set the default browser
    export BROWSER=brave-browser

    # make it so that ctrl+alt+h,j,k,l move between words in the terminal

    bind \b backward-word
    bind \f forward-word
    bind -k nul backward-kill-word

    fzf_key_bindings
    # eval /home/matthandzel/anaconda3/bin/conda "shell.fish" hook $argv | source
end
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
# <<< conda initialize <<<
