{
  inputs,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    # Development & System Tools
    bitwise
    eza
    entr
    fd
    file
    fzf
    gtt
    gifsicle
    gtrash
    hexdump
    jdk17
    lazygit
    nitch
    nix-prefetch-github
    ripgrep
    tdf
    todo
    toipe
    valgrind
    yazi
    yt-dlp-light
    xxd
    alejandra # nixpkgs build; the pinned alejandra/3.0.0 input 403s on crates.io

    # C / C++
    gcc
    gnumake
    pkg-config

    # Python
    python3
    # conda # Might be heavy, but keeping for dev

    # Utilities
    cmatrix
    ffmpeg
    killall
    man-pages
    ncdu
    openssl
    unzip
    zip
    wget
    xdg-utils

    # Node.js
    nodejs_22

    # System info
    fastfetch
    nix-index

    # Multiplexer & SSH
    tmux
    openssh
    sshfs

    # Dev specific
    go
    gopls
    delve

    # Life logging (CLI parts)
    # inputs.lifelog.packages.x86_64-linux.lifelog-collector
    v4l-utils

    trash-cli
    waypipe # Useful for X11/Wayland forwarding if needed
  ];
}
