#!/bin/bash

# Name of the tmux session
SESSION_NAME="yazi"

# Check if the tmux session exists (tmux list-sessions | grep -q "^$SESSION_NAME")
tmux has-session -t $SESSION_NAME 2>/dev/null

if [ $? != 0 ]; then
	# Create a new tmux session, detached
	tmux new-session -d -s $SESSION_NAME
	# Send keys to tmux session to start neovim with the note file
	tmux send-keys -t $SESSION_NAME "yazi" C-m
fi

# Launch your terminal and attach it to the tmux session
alacritty -e bash -c "echo -ne '\033]0;yazi\007'; tmux attach -t $SESSION_NAME"
