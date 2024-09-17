#!/usr/bin/env zsh

# Function to display messages
display_message() {
    if command -v gum &> /dev/null; then
        gum style --border normal --padding "1 1" --margin "1 2" --border-foreground 212 "$1"
    else
        echo "$1"
    fi
}

# Check for shell.nix in the current directory
if [[ -f "shell.nix" ]]; then
    display_message "🔧 Found 'shell.nix' in the current directory. Using this file to run nix-shell."
    
    # Run nix-shell with nvim
    nix-shell shell.nix --run "nvim && $SHELL"
else
    display_message "⚠️ No 'shell.nix' found. Running nvim directly."
    nvim
fi

$SHELL
