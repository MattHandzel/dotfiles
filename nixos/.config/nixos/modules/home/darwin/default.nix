# The macOS-only half of the Home Manager config, imported from
# modules/home/default.nix when `pkgs.stdenv.hostPlatform.isDarwin`.
#
# The Linux counterpart is the `linuxOnly` list in that same file (Hyprland,
# waybar, swaync, fuzzel, …). Everything shared lives in the `shared` list and
# is not repeated here.
{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./aerospace.nix # tiling WM config (~/.aerospace.toml)
    ./aerospace-watchdog.nix # relaunch AeroSpace when it crashes or hangs (upstream #1311)
    ./karabiner.nix # caps⇄esc swap + US/Polish toggle
    ./compat-shims.nix # wl-copy/notify-send/xdg-open/... under their Linux names
    ./zen-config.nix # Zen prefs, macOS profile root
    ./automations.nix # calendar-agenda / disk-space-alert (system services on NixOS)
    ./memory-guard.nix # end a runaway batch job before macOS pauses apps on swap exhaustion
    ./login-items.nix # Beeper + Hammerspoon at login (AeroSpace does its own)
    ./bitwarden.nix # Bitwarden.app at login + Dia native-messaging bridge (Touch ID unlock in Dia)
    ./no-app-resume.nix # kill "Reopen windows when logging back in", even after `sudo reboot`
    ./raycast-scripts.nix # Raycast Script Commands (timer & co.), twin of vicinae.nix
    ./wispr-clipboard-sync.nix # every Wispr Flow dictation -> clipboard -> Raycast history
    ./wispr-meeting-sync.nix # Wispr Flow meeting summaries + transcripts -> vault, calendar note, daily note
    ./wispr-learn.nix # corrections made in Neovim -> Wispr Flow dictionary (its own learner cannot see kitty)
    ./oops.nix # alt-backtick / Raycast "Oops": last 90 s of keys -> Claude -> problem log + fix
    ./espanso.nix # ;; text-expansion triggers (nix-managed base.yml; Espanso.app + its own agent)
    ./sketchybar.nix # the status bar (waybar's replacement): config + launchd agent
    ./borders.nix # JankyBorders colours/width (~/.config/borders/bordersrc)
    ./kms-ingest.nix # phone captures in ~/ShareComputer/kms-inbox -> vault raw_capture (kms ingest)
    ./downloads-to-phone.nix # new ~/Downloads files -> ~/ShareComputer/downloads -> phone
  ];

  # Home Manager's syncthing module supports darwin (it emits a launchd agent).
  # Deliberately NOT the Syncthing cask as well — two instances fighting over
  # port 8384 is a slow, quiet failure. On the NixOS laptop this is a SYSTEM
  # service (hosts/laptop/default.nix), which is why it is declared here rather
  # than in the shared list.
  services.syncthing = {
    enable = true;
    settings = {
      # The default 1% of this 926 GB disk (9.3 GB) is more than the Mac keeps
      # free while the LinuxHome mirror shares the SSD, and it stops every
      # folder. The synced data here is KBs; 1 GB is plenty of headroom.
      options.minHomeDiskFree = {
        value = 1;
        unit = "GB";
      };
      devices = {
        # Same ID the server declares (hosts/server/default.nix). The phone has
        # to accept "matts-mac" once, then accept the Recordings share.
        "Pixel 9a" = {id = "OUXTWJX-MARBGAE-ANVOBSS-ANCZDVY-QGJGWNC-YXK62MC-IPV22XX-PV3RMA5";};
      };
      folders = {
        # The phone's "share computer" folder. Only kms-inbox/ (phone capture
        # JSON) is synced — see the .stignore written below; the other 5.8 GB
        # of photos/videos stay on the phone. Send-receive so the Mac-side
        # ingester's deletes of processed captures reach the phone, as the
        # NixOS laptop's did.
        "qbf3n-3ef5e" = {
          label = "ShareComputer";
          path = "~/ShareComputer";
          devices = ["Pixel 9a"];
          minDiskFree = {
            value = 1;
            unit = "GB";
          };
        };
      };
    };
  };

  # A real file, not a store symlink: Syncthing won't follow a symlinked
  # .stignore. Written before launchd (re)starts syncthing.
  # This file is a WHITELIST: the trailing `*` ignores everything, and only the
  # `!`-negated paths sync. A path that is not negated here is a silent no-op --
  # files dropped at the root of ~/ShareComputer sit there forever and never
  # reach the phone (which is exactly what happened to an audiobook on
  # 2026-09-16). Negate /downloads, never `*`: the phone side of this folder
  # holds ~4.9 GB of photos and video that must stay on the phone.
  home.activation.shareComputerStignore = lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
    run mkdir -p "$HOME/ShareComputer" "$HOME/ShareComputer/downloads"
    run rm -f "$HOME/ShareComputer/.stignore"
    run install -m 644 ${pkgs.writeText "sharecomputer-stignore" ''
      !/kms-inbox
      !/downloads
      *
    ''} "$HOME/ShareComputer/.stignore"
  '';

  home.sessionPath = [
    # Homebrew's Apple-silicon prefix. Casks put CLI helpers here (borders,
    # aerospace) and macOS login shells do not add it on their own.
    "/opt/homebrew/bin"
  ];

  home.packages = [
    # `pick`'s backend and the notifier are installed system-wide in
    # modules/darwin/packages.nix; these are the user-level extras the shared
    # scripts reach for.
    pkgs.pandoc
    # adb over Wireless debugging (phone Night Light, 2026-09-13 Oops)
    pkgs.android-tools
    # DDC/CI brightness for the external monitor (DELL U3225QE): used by
    # ~/.local/bin/brightness and ~/.hammerspoon/brightness_blackout.lua
    pkgs.m1ddc
  ];

  # Hammerspoon and `brightness` call it before `rebuild` puts it on PATH.
  home.file.".local/bin/m1ddc".source = "${pkgs.m1ddc}/bin/m1ddc";
}
