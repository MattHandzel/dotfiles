{ inputs, pkgs, ... }: 
let 
  _2048 = pkgs.callPackage ../../pkgs/2048/default.nix {}; 
in
{
  home.packages = (with pkgs; [
    _2048
    
    audacity
    bitwise                           # cli tool for bit / hex manipulation
    cbonsai                           # terminal screensaver
    evince                            # gnome pdf viewer
    eza                               # ls replacement
    entr                              # perform action when file change
    fd                                # find replacement
    file                              # Show file information 
    fzf                               # fuzzy finder
    gtt                               # google translate TUI
    gifsicle                          # gif utility
    gimp
    gtrash                            # rm replacement, put deleted files in system trash
    hexdump
    jdk17                             # java
    lazygit
    libreoffice
    nautilus     # file manager
    nitch                             # systhem fetch util
    nix-prefetch-github
    pipes                             # terminal screensaver
    prismlauncher                     # minecraft launcher
    ripgrep                           # grep replacement
    soundwireserver                   # pass audio to android phone
    tdf                               # cli pdf viewer
    todo                              # cli todo list
    toipe                             # typing test in the terminal
    valgrind                          # c memory analyzer
    yazi                              # terminal file manager
    yt-dlp-light
    zenity
    winetricks
    wineWowPackages.wayland

    # C / C++
    gcc
    gnumake

    # Python
    python3

    bleachbit                         # cache cleaner
    cmatrix
    gparted                           # partition manager
    ffmpeg
    imv                               # image viewer
    killall
    libnotify
	  man-pages					            	  # extra man pages
    mpv                               # video player
    ncdu                              # disk space
    openssl
    pamixer                           # pulseaudio command line mixer
    pavucontrol                       # pulseaudio volume controle (GUI)
    playerctl                         # controller for media players
    wl-clipboard                      # clipboard utils for wayland (wl-copy, wl-paste)
    cliphist                          # clipboard manager
    poweralertd
    qalculate-gtk                     # calculator
    unzip
    wget
    xdg-utils
    xxd
    inputs.alejandra.defaultPackage.${system}

    brave # 
    wofi-emoji

    gammastep

    # nodePackages.npm
    nodejs_22

    ddcutil # for talking with external monitors
    wlr-randr # for wayland monitor management

ntfs3g
pika-backup
helvetica-neue-lt-std
# terminal stuff
stow
thefuck
yazi
# hyprshade
# grimblast
### data collection stuff
aw-watcher-afk
aw-watcher-window
activitywatch
nix-index


zoom
# cura
syncthing
obs-studio
libreoffice
slack
anki
obsidian
neomutt
feh
texliveFull

morgen


wlroots
wl-gammactl
mako


#  gcc
#  clang
#  glib
#  glibc
#  gdb
#  valgrind
#  cmake
# libxcrypt
# clang-tools
# nss
# postgresql
# libpqxx
#
#
#
stylua

vimPlugins.nvchad
vimPlugins.nvchad-ui
#
#
# gnumake42
# glibcLocales
#
# cargo
# openconnect_openssl
# ninja
# gh
  ]);
}
