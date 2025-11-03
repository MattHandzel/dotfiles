{
  inputs,
  pkgs,
  ...
}: let
  _2048 = pkgs.callPackage ../../pkgs/2048/default.nix {};
in {
  home.packages = with pkgs; [
    _2048

    audacity
    bitwise # cli tool for bit / hex manipulation
    cbonsai # terminal screensaver
    evince # gnome pdf viewer
    eza # ls replacement
    entr # perform action when file change
    fd # find replacement
    file # Show file information
    fzf # fuzzy finder
    gtt # google translate TUI
    gifsicle # gif utility
    gimp
    gtrash # rm replacement, put deleted files in system trash
    hexdump
    jdk17 # java
    lazygit
    libreoffice
    nautilus # file manager
    nitch # systhem fetch util
    nix-prefetch-github
    pipes # terminal screensaver
    ripgrep # grep replacement
    soundwireserver # pass audio to android phone
    tdf # cli pdf viewer
    todo # cli todo list
    toipe # typing test in the terminal
    valgrind # c memory analyzer
    yazi # terminal file manager
    yt-dlp-light
    zenity
    winetricks
    wineWowPackages.wayland

    # C / C++
    gcc
    gnumake

    # Python
    python3
    conda

    bleachbit # cache cleaner
    cmatrix
    gparted # partition manager
    ffmpeg-full
    imv # image viewer
    killall
    libnotify
    man-pages # extra man pages
    mpv # video player
    ncdu # disk space
    openssl
    pamixer # pulseaudio command line mixer
    pavucontrol # pulseaudio volume controle (GUI)
    playerctl # controller for media players
    wl-clipboard # clipboard utils for wayland (wl-copy, wl-paste)
    cliphist # clipboard manager
    poweralertd
    qalculate-gtk # calculator
    unzip
    zip
    wget
    xdg-utils
    xxd
    inputs.alejandra.defaultPackage.${system}

    brave #
    slack
    wofi-emoji

    gammastep

    # nodePackages.npm
    nodejs_22

    ddcutil # for talking with external monitors
    wlr-randr # for wayland monitor management

    pandoc # markdown to pdf, norg to pdf

    ntfs3g
    pika-backup
    helvetica-neue-lt-std
    # terminal stuff
    stow
    yazi
    # hyprshade
    # grimblast
    ### data collection stuff
    aw-watcher-afk
    aw-watcher-window
    activitywatch
    nix-index

    zoom-us
    # cura
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
    # mako

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
    luarocks-nix

    # prusa-slicer # prusa-slicer

    openssh

    zathura
    calcurse # Calendar in the terminal

    sshfs
    fastfetch
    # whatsapp-for-linux

    inputs.zen-browser.packages."${system}".default # This is for zen-browser
    tigervnc
    espanso-wayland

    # planify
    speedcrunch
    ntfy-sh

    kdePackages.xdg-desktop-portal-kde # xdg-desktop-portal
    firefox

    # xdg-desktop-port-kde
    # zulu # thinkorswim

    #
    #
    # gnumake42
    # glibcLocales
    #
    # cargo
    pkg-config
    # openconnect_openssl
    # ninja
    # gh

    # inputs.notion-repackaged.packages.x86_64-linux.notion-repackaged
    kdePackages.kdenlive
    qbittorrent-enhanced
    # platformio

    docker
    vdhcoapp # for browser extensio

    go
    gopls
    delve
    gcc
    sc-im

    logkeys # keylogger
    # inputs.lifelog.packages.x86_64-linux.lifelog-logger
    # inputs.kms-capture.packages.x86_64-linux.kms-capture
    # inputs.lifelog.packages.x86_64-linux.lifelog-server
    v4l-utils
    # rustup

    rust-analyzer
    rustfmt
    rustc

    xdg-desktop-portal
    kdePackages.xdg-desktop-portal-kde #    xdg-desktop-portal-kde

    # surrealdb

    trash-cli
    mermaid-cli # for mermaid diagrams
    # busybox # common utils
    foliate # ebook reader
    # other ebook readers:
    calibre
    nwg-look

    crow-translate
    ollama

    windsurf
    electron
    portaudio
    wtype # type virtual things on the computer
    taskwarrior
    vit

    python313Packages.debugpy

    procps # needed for pidof, otherwise grimblast breaks

    python312Packages.webrtcvad
    python312Packages.requests
    python312Packages.setuptools # for stt-rrecord

    gemini-cli
  ];
}
