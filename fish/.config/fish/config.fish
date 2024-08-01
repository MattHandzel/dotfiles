if status is-interactive
    # Commands to run in interactive sessions can go here
    alias rebuild="sudo nixos-rebuild switch --flake ~/dotfiles/nixos/.config/nixos/#main"
    alias gitca="git commit -a -m"
    alias gitaca="git add . && git commit -a -m"
    alias gitacam="git add . && git commit -a -m 'This is a boilerplate git commit message' && git push"
    alias gitp="git push"
    alias gits="git status"
    alias notetaker="./notetaker.sh"
    alias ls="lsd"
    alias lst="lsd --tree --depth 2"
    alias nix-shell="nix-shell --run fish"

    alias n="nvim"
    alias py="python3"
    # Set the default editor
    export EDITOR=nvim

    export TMUX_PLUGIN_MANAGER_PATH="~/.config/tmux/.tmux/"

    # Set the default browser
    export BROWSER=brave-browser
    

    set -gx PATH $PATH ~/latexrun/
    # make it so that ctrl+alt+h,j,k,l move between words in the termina
    set -gx PATH $PATH ~/anaconda3/bin/pygmentize
    set -gx PATH $PATH ~/yazi/target/release/
    set -gx PATH $PATH ~/dotfiles/nix-shells/

    # bind \cf "~/tmux_sessionizer.sh"
    bind \cn "yazi ."

    bind \el "clear"

    bind \b backward-word
    bind \f forward-word
    bind -k nul backward-kill-word
    zoxide init --cmd cd fish | source
    fzf_key_bindings
    fish_default_key_bindings
    # eval /home/matthandzel/anaconda3/bin/conda "shell.fish" hook $argv | source
end
# THEME PURE #
set fish_function_path /home/matth/.config/fish/functions/theme-pure/functions/ $fish_function_path
source /home/matth/.config/fish/functions/theme-pure/conf.d/pure.fish
