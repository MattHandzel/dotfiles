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
      cleanup = "zap";
    };

    taps = builtins.attrNames config.nix-homebrew.taps;

    casks = [
      # ── browsers ──
      "zen-browser"
      "google-chrome"
      "brave-browser"

      # ── daily drivers ──
      "obsidian"
      "slack"
      "beeper"
      "claude"
      "cursor"
      "windsurf"
      "wispr-flow"
      "bitwarden"
      "zoom"
      "discord"
      "thunderbird"

      # ── the Phase 6 keyboard/window stack ──
      "raycast"
      "nikitabobko/tap/aerospace"
      "karabiner-elements"
      "espanso"

      # ── infrastructure ──
      "orbstack"
      "activitywatch"
      "google-drive"
      "tailscale-app"

      # ── nice to have (Phase 8) ──
      "anki"
      "gimp"
      "libreoffice"
      "obs"
      "calibre"
      "prusaslicer"
      "qbittorrent"
      "utm"
      "aldente" # battery charge limit — the tlp 60/80 thresholds
      "iina" # mpv-based video player
      "stats" # menu-bar sensors, replacing waybar's
      "homerow" # keyboard-click any UI element
      "shottr" # OCR + annotated screenshots (satty + ocr-screenshot)
      "jankyborders" # focused-window border in Catppuccin Mauve
      "ice" # hide menu-bar clutter
    ];

    # Syncthing is deliberately NOT a cask: Home Manager's services.syncthing
    # runs it on darwin too, and having both fight over port 8384 is a
    # long-running, hard-to-see failure.
    brews = [];
  };
}
