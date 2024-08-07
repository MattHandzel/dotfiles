
DISABLE_MAGIC_FUNCTIONS=true
export "MICRO_TRUECOLOR=1"

typeset -U path cdpath fpath manpath

for profile in ${(z)NIX_PROFILES}; do
  fpath+=($profile/share/zsh/site-functions $profile/share/zsh/$ZSH_VERSION/functions $profile/share/zsh/vendor-completions)
done

HELPDIR="/nix/store/x011bx2xa0xw2qwlk7vzkgpf7l005qxb-zsh-5.9/share/zsh/$ZSH_VERSION/help"





# Oh-My-Zsh/Prezto calls compinit during initialization,
# calling it twice causes slight start up slowdown
# as all $fpath entries will be traversed again.

source /nix/store/vv28ikvsqidxmkgk17pjrs9ds542c1yi-zsh-autosuggestions-0.7.0/share/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history)


# oh-my-zsh extra settings for plugins

# oh-my-zsh configuration generated by NixOS
plugins=(git fzf)


source $ZSH/oh-my-zsh.sh





# History options should be set in .zshrc and after oh-my-zsh sourcing.
# See https://github.com/nix-community/home-manager/issues/177.
HISTSIZE="10000"
SAVEHIST="10000"

HISTFILE="$HOME/.zsh_history"
mkdir -p "$(dirname "$HISTFILE")"

setopt HIST_FCNTL_LOCK
setopt HIST_IGNORE_DUPS
unsetopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
unsetopt HIST_EXPIRE_DUPS_FIRST
setopt SHARE_HISTORY
unsetopt EXTENDED_HISTORY



eval $(thefuck --alias) # gets fuck command running

eval "$(/nix/store/3cf00yza6r1j0w0fla0d4h1f8nai7pkx-zoxide-0.9.4/bin/zoxide init zsh )"

if [[ $TERM != "dumb" ]]; then
  eval "$(/etc/profiles/per-user/matth/bin/starship init zsh)"
fi

if test -n "$KITTY_INSTALLATION_DIR"; then
  export KITTY_SHELL_INTEGRATION="no-rc"
  autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
  kitty-integration
  unfunction kitty-integration
fi

# This function is called whenever a command is not found.
command_not_found_handler() {
  local p=/nix/store/f7hly8dm2x4nsag8vvdc7i2w2sjx584c-command-not-found/bin/command-not-found
  if [ -x $p -a -f /nix/var/nix/profiles/per-user/root/channels/nixos/programs.sqlite ]; then
    # Run the helper program.
    $p "$@"
  else
    echo "$1: command not found" >&2
    return 127
  fi
}


# Aliases
alias -- 'c'='clear'
alias -- 'cat'='bat'
alias -- 'cd'='z'
alias -- 'code'='codium'
alias -- 'dsize'='du -hs'
alias -- 'findw'='grep -rl'
alias -- 'ga'='git add'
alias -- 'gaa'='git add --all'
alias -- 'gb'='git branch'
alias -- 'gc'='git commit'
alias -- 'gch'='git checkout'
alias -- 'gchb'='git checkout -b'
alias -- 'gcm'='git commit -m'
alias -- 'gcma'='git add --all && git commit -m'
alias -- 'gcoe'='git config user.email'
alias -- 'gcon'='git config user.name'
alias -- 'gm'='git merge'
alias -- 'gpl'='git pull'
alias -- 'gplo'='git pull origin'
alias -- 'gps'='git push'
alias -- 'gpso'='git push origin'
alias -- 'gpst'='git push --follow-tags'
alias -- 'gs'='git status'
alias -- 'gtag'='git tag -ma'
alias -- 'icat'='kitten icat'
alias -- 'l'='eza --icons  -a --group-directories-first -1'
alias -- 'll'='eza --icons  -a --group-directories-first -1 --no-user --long'
alias -- 'ls'='lsd'
alias -- 'lst'='lsd --tree --depth'
alias -- 'n'='nvim'
alias -- 'nix-clean'='sudo nix-collect-garbage && sudo nix-collect-garbage -d && sudo rm /nix/var/nix/gcroots/auto/* && nix-collect-garbage && nix-collect-garbage -d'
alias -- 'nix-flake-update'='sudo nix flake update /nix/store/iq5823iar0f9iv1jr8crcii5pmqd228c-7nll4fbbv92bf50kpyszsgs3gbawyx0d-source#'
alias -- 'nix-shell'='nix-shell --run zsh'
alias -- 'ns'='nix-shell --run zsh'
alias -- 'open'='xdg-open'
alias -- 'pdf'='tdf'
alias -- 'piv'='python -m venv .venv'
alias -- 'psv'='source .venv/bin/activate'
alias -- 'py'='python'
alias -- 'rebuild'='sudo nixos-rebuild switch --flake /nix/store/iq5823iar0f9iv1jr8crcii5pmqd228c-7nll4fbbv92bf50kpyszsgs3gbawyx0d-source#laptop'
alias -- 'rebuildu'='sudo nixos-rebuild switch --upgrade --flake /nix/store/iq5823iar0f9iv1jr8crcii5pmqd228c-7nll4fbbv92bf50kpyszsgs3gbawyx0d-source#laptop'
alias -- 'record'='wf-recorder --audio=alsa_output.pci-0000_08_00.6.analog-stereo.monitor -f $HOME/Videos/$(date +'\''%Y%m%d%H%M%S_1.mp4'\'')'
alias -- 'tree'='eza --icons --tree --group-directories-first'
alias -- 'tt'='gtrash put'

# Named Directory Hashes


source /nix/store/dk9jcdv1g4rh6fxsi28vlnx6k0b5ri6n-zsh-syntax-highlighting-0.8.0/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
ZSH_HIGHLIGHT_HIGHLIGHTERS+=()




