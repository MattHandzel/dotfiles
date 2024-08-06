#!/usr/bin/env zsh

# Check for shell.nix in the current directory
if [[ -f "shell.nix" ]]; then
    # Use gum to display a nice message
    if ! command -v gum &> /dev/null ; then
      # If gum in not installed then say it very boringly
      echo "🔧 Found 'shell.nix' in the current directory. Using this file to run nix-shell."
    else
      gum style --border normal --padding "1 1" --margin "1 2" --border-foreground 212 "🔧 Found 'shell.nix' in the current directory. Using this file to run nix-shell."
    fi


    
    # Run nix-shell
    nix-shell shell.nix --run $SHELL
fi

$SHELL
