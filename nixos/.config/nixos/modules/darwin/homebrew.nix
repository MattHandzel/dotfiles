# Declarative Homebrew.
#
# WHY CASKS AT ALL, in a flake this committed to Nix: the apps below are
# notarized, sandboxed, self-updating macOS bundles (Zen, Slack, Raycast,
# Karabiner's DriverKit extension, Google Drive's file provider). nixpkgs either
# does not package them for darwin or packages them in a way that breaks code
# signing, which breaks the very permissions — Accessibility, Input Monitoring,
# Screen Recording — that the Phase 6 keyboard setup depends on. A cask is the
# honest tool here; the LIST of casks is still declarative and version-controlled.
#
# Anything that is a plain CLI or a well-behaved nixpkgs darwin build stays in
# Nix (see modules/darwin/packages.nix): kitty, mpv, tailscale CLI,
# terminal-notifier, choose-gui, kanata.
{
  config,
  inputs,
  username,
  ...
}: {
  imports = [inputs.nix-homebrew.darwinModules.nix-homebrew];

  nix-homebrew = {
    enable = true;
    enableRosetta = false; # Apple silicon only; no x86 brew prefix
    user = username;

    # Taps come from pinned flake inputs, and mutableTaps = false means `brew
    # tap` cannot drift them out from under the flake. Without this the tap
    # contents are whatever `brew update` last fetched.
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
      "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
      "nikitabobko/homebrew-tap" = inputs.nikitabobko-tap;
      "FelixKratz/homebrew-formulae" = inputs.felixkratz-tap;
    };
    mutableTaps = false;
  };

  homebrew = {
    enable = true;
    onActivation = {
      # The flake pins the taps; letting brew self-update on every switch would
      # make the same commit produce different apps on different days.
      autoUpdate = false;
      upgrade = false;
      # Anything installed by hand and not listed here gets removed. That is the
      # point: the list below is the truth about what is on this machine.
      # LOCAL, UNCOMMITTED MIGRATION OVERRIDE for the first switch.
      # superhuman, linear, morgen, spotify and claude-code are installed but
      # absent from the cask list below; "zap" would uninstall them and delete
      # their application data. Revert to "zap" once the list is reconciled.
      cleanup = "none";
    };

    taps = builtins.attrNames config.nix-homebrew.taps;

    # This list is reconciled against `brew list --cask` on matts-mac
    # (2026-09-10). Every entry below is actually installed; every installed
    # cask is listed. That is the precondition for putting `cleanup` back to
    # "zap" — until then a mismatch silently means "zap would delete an app".
    casks = [
      # ── browsers ──
      "thebrowsercompany-dia" # 2026-09-12: migrating from Zen to Dia (projects/zen-to-arc-migration in the vault; "dia" is a diagram editor)
      "zen" # stays installed as the rollback until Dia has proven itself; the cask is "zen", not "zen-browser" (renamed upstream)
      "google-chrome"
      "brave-browser"

      # ── daily drivers ──
      "obsidian"
      "slack"
      "beeper"
      "superhuman" # mail client (NOT Thunderbird — Matt, 2026-09-09)
      "linear"
      "morgen" # calendar; also the default .ics/webcal handler
      "spotify"
      "whatsapp"
      "discord"
      "zoom"
      "clockify"
      "claude" # Claude Desktop
      "claude-code@latest" # the CLI, so `rebuild` keeps it current
      "cursor"
      "windsurf"
      "devin-desktop"
      "wispr-flow"
      "bitwarden"
      "thunderbird" # profiles migrated; kept as an archive reader

      # ── the Phase 6 keyboard/window stack ──
      "raycast"
      "nikitabobko/tap/aerospace"
      "karabiner-elements"
      "homerow" # keyboard-click any UI element
      "kitty" # the cask, not nixpkgs: the nix build loses code signing and
      # with it Accessibility/Screen-Recording grants
      # Espanso IS in use (reality check 2026-09-12): the 2026-09-10 note here
      # claimed Raycast Snippets had replaced it, but Espanso.app was installed,
      # its LaunchAgent (com.federicoterzi.espanso) running and 33 triggers live.
      # The ;; matches are now nix-managed in modules/home/darwin/espanso.nix.
      "espanso"

      # ── infrastructure ──
      "orbstack"
      "activitywatch"
      "google-drive"
      "tailscale-app"
      "utm"

      # ── media, docs, making ──
      "anki"
      "gimp"
      "libreoffice"
      "obs"
      "calibre"
      "audacity"
      "iina" # mpv-based video player
      "prusaslicer"
      "ultimaker-cura"
      # qBittorrent's casks (qbittorrent, qbittorrent@lt20) were DISABLED by
      # Homebrew on 2026-09-01 for failing the Gatekeeper check. Transmission
      # is the signed, maintained stand-in.
      "transmission"

      # ── menu bar / desktop polish ──
      "aldente" # battery charge limit — the tlp 60/80 thresholds
      "stats" # menu-bar sensors, replacing waybar's
      "shottr" # OCR + annotated screenshots (satty + ocr-screenshot)
      "jordanbaird-ice" # hide menu-bar clutter; cask is "jordanbaird-ice"
      "mysides" # scripted Finder sidebar order
      "linearmouse" # trackpad/mouse speed past the System Settings cap (2026-09-13, carolannejiang.com/computer-things)
      "flux-app" # f.lux: sunset colour shift; goes warmer (1900K) than Night Shift and ramps (2026-09-13 Oops)
      "bluesnooze" # Bluetooth off while asleep: the Totem's BLE link woke the Mac every 60 s after lid close (2026-09-14 Oops)

      # ── fonts and glyphs ──
      "font-jetbrains-mono-nerd-font"
      "font-inter"
      "sf-symbols" # Apple's glyph set, for the odd item the Nerd Font lacks
      "font-sketchybar-app-font" # per-app glyphs beside each workspace number
    ];

    # Syncthing is deliberately NOT a cask: Home Manager's services.syncthing
    # runs it on darwin too, and having both fight over port 8384 is a
    # long-running, hard-to-see failure.
    brews = [
      # The status bar. A formula, not a cask: it is a bare binary that draws
      # its own window over the notch strip. Config + launchd agent are in
      # modules/home/darwin/sketchybar.nix.
      "FelixKratz/formulae/sketchybar"
      # The focused-window border, in Catppuccin Mauve. Also a formula.
      "FelixKratz/formulae/borders"
      # Reads Calendar.app for the bar's "next event" item when the read-only
      # Google agenda file is missing or stale.
      "ical-buddy"
      # Touch ID for sudo inside tmux: without pam_reattach the prompt appears
      # in a session that cannot talk to the fingerprint sensor.
      "pam-reattach"
      # gpg needs a GUI pinentry on macOS or every `pass show` fails silently.
      "pinentry-mac"
      # The GUI self-test toolkit Claude uses to drive and verify the desktop.
      "cliclick"
      "terminal-notifier"
      "tesseract"
      "duti" # default-app bindings
      "defaultbrowser"
      "dockutil" # scripted Dock contents
      # Verification and transfer tooling from the migration.
      "b3sum"
      "xxhash"
      "rsync" # macOS ships rsync 2.6.9; -aHAX needs a modern one
      "coreutils"
      "jq"
    ];
  };
}
