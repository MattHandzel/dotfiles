# The macOS-only half of the Home Manager config, imported from
# modules/home/default.nix when `pkgs.stdenv.hostPlatform.isDarwin`.
#
# The Linux counterpart is the `linuxOnly` list in that same file (Hyprland,
# waybar, swaync, fuzzel, …). Everything shared lives in the `shared` list and
# is not repeated here.
{pkgs, ...}: {
  imports = [
    ./aerospace.nix # tiling WM config (~/.aerospace.toml)
    ./karabiner.nix # caps⇄esc swap + US/Polish toggle
    ./compat-shims.nix # wl-copy/notify-send/xdg-open/... under their Linux names
    ./zen-config.nix # Zen prefs, macOS profile root
    ./automations.nix # calendar-agenda / disk-space-alert (system services on NixOS)
    ./sketchybar.nix # the status bar (waybar's replacement): config + launchd agent
    ./borders.nix # JankyBorders colours/width (~/.config/borders/bordersrc)
  ];

  # Home Manager's syncthing module supports darwin (it emits a launchd agent).
  # Deliberately NOT the Syncthing cask as well — two instances fighting over
  # port 8384 is a slow, quiet failure. On the NixOS laptop this is a SYSTEM
  # service (hosts/laptop/default.nix), which is why it is declared here rather
  # than in the shared list.
  services.syncthing.enable = true;

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
  ];
}
