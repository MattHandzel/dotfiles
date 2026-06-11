{
  inputs,
  pkgs,
  ...
}: let
  # _2048 = pkgs.callPackage ../../pkgs/2048/default.nix {};
  project-asset-generator = pkgs.callPackage ../../pkgs/project-asset-generator/default.nix {
    src = inputs.project-asset-generator-src;
  };

  # Learn This extension, packaged as an unsigned local XPI (MAT-826). Source is
  # vendored under pkgs/zen-learn-extension/src/ so the install is reproducible.
  learn-this-extension = pkgs.callPackage ../../pkgs/zen-learn-extension/default.nix {};

  # Zen browser with declaratively force-installed extensions (MAT-572 — Saul's
  # Chrome-extension list, ported). The zen flake exposes the *wrapped* browser
  # as `default`, whose `.override` only takes wrapFirefox args (no `policies`),
  # so we re-wrap the same `beta-unwrapped` derivation `default` is built from
  # (mirroring the flake's own `beta = wrapFirefox beta-unwrapped { icon...; }`)
  # and add `extraPolicies` — nixpkgs writes them into the browser's
  # policies.json, whose ExtensionSettings auto-installs each add-on from
  # addons.mozilla.org on launch. Only these 4 are declared, so existing
  # manually-installed add-ons (uBlock Origin, Stylus, …) are left untouched.
  # New Tab Override needs its target URL set once in its own options page —
  # Firefox policy can't set the new-tab URL directly.
  #
  # MAT-826: "Learn This" is a *local, unsigned* extension (no AMO listing), so
  # it is force-installed from a file:// XPI built by the local
  # zen-learn-extension derivation, and `extraPrefs` relaxes
  # xpinstall.signatures.required so the unsigned XPI is accepted. This mirrors
  # what nixpkgs' own `nixExtensions` path does, but without switching to that
  # mode (which would block all manually-installed add-ons).
  zenWithExtensions = let
    system = pkgs.stdenv.hostPlatform.system;
    # id = the add-on's internal GUID (the ExtensionSettings key Firefox matches
    # against the installed xpi); slug = its addons.mozilla.org URL slug.
    forceExt = id: slug: {
      name = id;
      value = {
        install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
        installation_mode = "force_installed";
      };
    };
  in
    pkgs.wrapFirefox inputs.zen-browser.packages.${system}.beta-unwrapped {
      icon = "zen-browser";
      # Accept the unsigned local "Learn This" XPI (MAT-826). Without this the
      # file:// force_install below is rejected as an unsigned add-on.
      extraPrefs = ''
        lockPref("xpinstall.signatures.required", false);
      '';
      extraPolicies.ExtensionSettings = builtins.listToAttrs [
        (forceExt "{d7742d87-e61d-4b78-b8a1-b469842139fa}" "vimium-ff") # Vimium
        (forceExt "addon@darkreader.org" "darkreader") # Dark Reader
        (forceExt "{7be2ba16-0f1e-4d93-9ebc-5164397477a9}" "videospeed") # Video Speed Controller
        (forceExt "newtaboverride@agenedia.com" "new-tab-override") # New Tab Override
        # Learn This — local unsigned XPI, force-installed from the Nix store.
        {
          name = "learn-this@matthandzel.com";
          value = {
            install_url = "file://${learn-this-extension}/learn-this@matthandzel.com.xpi";
            installation_mode = "force_installed";
          };
        }
      ];
    };
in {
  home.packages = with pkgs; [
    # _2048

    audacity
    bitwise # cli tool for bit / hex manipulation
    cbonsai # terminal screensaver
    sioyek # research-focused pdf viewer
    eza # ls replacement
    entr # perform action when file change
    fd # find replacement
    file # Show file information
    fzf # fuzzy finder
    # gtt # google translate TUI
    gifsicle # gif optimization (project-asset-generator)
    vhs # terminal GIF recording (project-asset-generator)
    marp-cli # markdown slides (project-asset-generator)
    tesseract # OCR for asset verification (project-asset-generator)
    project-asset-generator # generate-assets CLI (~/Projects/project-asset-generator)

    gimp
    gtrash # rm replacement, put deleted files in system trash
    hexdump
    jdk17 # java
    lazygit
    libreoffice
    kdePackages.dolphin # file manager
    # nitch # systhem fetch util
    nix-prefetch-github
    # pipes # terminal screensaver
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
    wineWow64Packages.wayland

    # C / C++
    gcc
    gnumake

    # Python
    python3
    conda

    bleachbit # cache cleaner
    cmatrix
    gparted # partition manager
    ffmpeg
    swayimg # wayland-native image viewer
    killall
    libnotify
    man-pages # extra man pages
    mpv # video player
    gdu # disk space (fast, SSD-optimized)
    openssl
    pwvucontrol # pipewire-native volume control (GUI)
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
    inputs.alejandra.defaultPackage.${pkgs.stdenv.hostPlatform.system}

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
    grim
    slurp
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
    satty # screenshot annotation tool
    texliveFull

    # morgen

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
    wasistlos
    dialect # GNOME translator — floating popup via SUPER+G submap
    crow-translate # Alt translator — floating popup via SUPER+SHIFT+G submap

    zenWithExtensions # zen-browser + declarative extensions (MAT-572; see let-block)
    tigervnc
    espanso-wayland

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
    platformio
    prusa-slicer

    docker

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
    taskwarrior3
    vit

    python313Packages.debugpy

    procps # needed for pidof, otherwise grimblast breaks

    python312Packages.webrtcvad
    python312Packages.requests
    python312Packages.setuptools # for stt-rrecord

    gemini-cli
    duf # better df
    procs # process viewer
    tig # git repository browser

    beeper
    gping
    code-cursor
    # claude-code # installing with npm is better
    chromium
  ];
}
