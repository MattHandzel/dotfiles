#!/usr/bin/env bash

if [[ $# -eq 1 ]]; then
    selected=$1
else
  selected=$(((find ~/ -mindepth 0 -maxdepth 2 ; find ~/ ./ ~/.config/ ~/Projects  ~/ImportantFiles ~/Obsidian ~/Job ~/UIUC ~/Code ~/Code/Python ~/dotfiles/ -mindepth 0 -maxdepth 4 -type d) ; zoxide query --list ; tmux list-sessions -F "#{session_name}") | awk '!seen[$0]++' | fzf --height 60% --reverse --border-label ' sessionizer ' --border --prompt '⚡  ')
fi

if [[ -z $selected ]]; then
    exit 0
fi

selected_name=$(basename "$selected" | tr . _)
tmux_running=$(pgrep tmux)

if [[ -z $TMUX ]] && [[ -z $tmux_running ]]; then
    tmux new-session -s $selected_name -c $selected "run-nix-shell-on-new-tmux-session"
    exit 0
fi

if ! tmux has-session -t=$selected_name 2> /dev/null; then
    tmux new-session -ds $selected_name -c $selected "run-nix-shell-on-new-tmux-session"
fi

tmux switch-client -t $selected_name 
