{
  inputs,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;

  # _2048 = pkgs.callPackage ../../pkgs/2048/default.nix {};
  project-asset-generator = pkgs.callPackage ../../pkgs/project-asset-generator/default.nix {
    src = inputs.project-asset-generator-src;
  };

  gdoc-sync = pkgs.callPackage ../../pkgs/gdoc-sync/default.nix {
    src = inputs.gdoc-sync-src;
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
        # Grammarly (MAT-1780). The browser extension is the ONLY surviving way to
        # reach a Grammarly Pro subscription — the Text Editor SDK shut down
        # 2024-01-10 and znck/grammarly (grammarly-languageserver) was archived
        # 2024-05-07, so there is no LSP path. Pairs with ghost-text.nvim, which
        # mirrors an nvim buffer into a textarea this extension can then check.
        (forceExt "87677a2c52b84ad3a151a4a72f5bd3c4@jetpack" "grammarly-1") # Grammarly
        (forceExt "ghosttext@bfred.it" "ghosttext") # GhostText — nvim <-> textarea
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

  sharedPkgs = with pkgs; [
    # ── shell / files ──
    bitwise # cli tool for bit / hex manipulation
    cbonsai # terminal screensaver
    cmatrix
    eza # ls replacement
    entr # perform action when file change
    fd # find replacement
    file # Show file information
    fzf # fuzzy finder
    gdu # disk space (fast, SSD-optimized)
    gtrash # rm replacement, put deleted files in system trash
    trash-cli
    duf # better df
    procs # process viewer
    tig # git repository browser
    gping
    fastfetch
    hexdump
    xxd
    stow
    unzip
    zip
    wget
    openssh
    openssl
    yazi # terminal file manager
    lazygit
    ripgrep # grep replacement
    rclone # cloud storage sync/mount
    sshfs

    # ── writing / documents ──
    pandoc # markdown to pdf, norg to pdf
    texliveFull
    harper # grammar checker (harper-ls LSP) — nvim prose, see nvim.nix
    languagetool # offline grammar engine for grammar-check (Super+C)
    tdf # cli pdf viewer
    neomutt
    calcurse # Calendar in the terminal
    mermaid-cli # for mermaid diagrams
    keymap-drawer # render ZMK/QMK keymaps to SVG (the TOTEM's zmk-config)
    helvetica-neue-lt-std

    # ── media ──
    ffmpeg
    yt-dlp-light
    gifsicle # gif optimization (project-asset-generator)
    vhs # terminal GIF recording (project-asset-generator)
    marp-cli # markdown slides (project-asset-generator)
    tesseract # OCR for asset verification (project-asset-generator)

    # ── tasks / notes ──
    taskwarrior3
    vit
    todo # cli todo list
    toipe # typing test in the terminal
    sc-im
    ntfy-sh
    gdoc-sync # markdown ↔ Google Docs sync CLI (~/Projects/gdoc-sync)

    # ── toolchains ──
    gcc
    gnumake
    pkg-config
    python3
    python313Packages.debugpy
    python312Packages.webrtcvad
    python312Packages.requests
    python312Packages.setuptools # for stt-rrecord
    portaudio
    nodejs_22
    go
    gopls
    delve
    rustc
    rustfmt
    rust-analyzer
    jdk17 # java
    stylua
    luarocks-nix
    nix-prefetch-github
    nix-index
    alejandra # nixpkgs build; the pinned alejandra/3.0.0 input 403s on crates.io

    # ── AI CLIs ──
    gemini-cli
    bitwarden-cli # `bw` — scriptable vault access + `rbw`-style automation
  ];

  # Wayland/Hyprland/systemd-bound, Linux-only builds, and every GUI app that
  # is a Homebrew cask on the Mac.
  linuxPkgs = with pkgs; [
    # ── Wayland / Hyprland ──
    wl-clipboard # clipboard utils for wayland (wl-copy, wl-paste)
    cliphist # clipboard manager
    grim
    slurp
    satty # screenshot annotation tool
    swayimg # wayland-native image viewer
    wtype # type virtual things on the computer
    wlr-randr # for wayland monitor management
    wlroots
    wl-gammactl
    gammastep
    pwvucontrol # pipewire-native volume control (GUI)
    playerctl # controller for media players
    poweralertd
    libnotify
    zenity
    wofi-emoji
    espanso-wayland
    nwg-look
    xdg-utils
    xdg-desktop-portal
    kdePackages.xdg-desktop-portal-kde
    kdePackages.dolphin # file manager
    kdePackages.kdenlive

    # ── Linux-only builds ──
    valgrind # c memory analyzer
    conda
    killall
    procps # needed for pidof, otherwise grimblast breaks
    man-pages # extra man pages
    logkeys # keylogger
    v4l-utils
    ddcutil # for talking with external monitors
    ntfs3g
    gparted # partition manager
    pika-backup
    bleachbit # cache cleaner
    soundwireserver # pass audio to android phone
    tigervnc
    electron
    docker # OrbStack replaces this on the Mac
    winetricks
    wineWow64Packages.wayland
    platformio
    ollama

    # ── data collection (systemd user services on Linux) ──
    aw-watcher-afk
    aw-watcher-window
    activitywatch

    # ── GUI apps that become casks on the Mac ──
    audacity
    sioyek # research-focused pdf viewer
    zathura
    qalculate-gtk # calculator
    mpv # video player (IINA on the Mac)
    gimp
    libreoffice
    obs-studio
    anki
    obsidian
    calibre
    readest
    foliate # ebook reader
    slack
    beeper
    zoom-us
    brave
    chromium
    google-chrome
    firefox
    bitwarden-desktop # password manager (GUI)
    code-cursor
    windsurf
    prusa-slicer
    qbittorrent-enhanced
    dialect # GNOME translator — floating popup via SUPER+G submap
    crow-translate # Alt translator — floating popup via SUPER+SHIFT+G submap
    wasistlos

    # ── needs Hyprland/Wayland at runtime, so must never be referenced on darwin ──
    zenWithExtensions # zen-browser + declarative extensions (MAT-572; see let-block)
    project-asset-generator # generate-assets CLI (needs grim/wtype/hyprland)
  ];

  # Nix-built GUI apps must go in environment.systemPackages (the
  # /Applications/Nix Apps trampoline), so they live in
  # modules/darwin/packages.nix. What is left for the user profile is nothing
  # yet — kept as an explicit empty list so the split is visible.
  darwinPkgs = [];
in {
  # sharedPkgs are the CLI/dev tools that build and behave the same on NixOS and
  # macOS. linuxPkgs are Wayland/Hyprland/systemd-bound tools, Linux-only
  # builds (valgrind, conda, psmisc), and every GUI app that becomes a Homebrew
  # cask on the Mac (see modules/darwin/homebrew.nix — a cask is used there
  # because those apps need Apple notarization for the permissions they ask
  # for). darwinPkgs is deliberately near-empty: Nix-built GUI apps must live in
  # `environment.systemPackages` for the /Applications/Nix Apps trampoline, so
  # they are declared in modules/darwin/packages.nix instead.
  home.packages =
    sharedPkgs
    ++ lib.optionals isLinux linuxPkgs
    ++ lib.optionals isDarwin darwinPkgs;
}
