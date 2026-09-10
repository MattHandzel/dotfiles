{
  pkgs,
  lib,
  ...
}: let
  # The declarative defaults. These are the same values as the monitor= and
  # workspace= lines in config.nix; they are duplicated here (rather than
  # sourced from one place) because these two files must be REGULAR files that
  # nwg-displays can rewrite, and anything Home Manager owns is a read-only
  # symlink into the store. Keeping them in sync is a two-line edit; making
  # them GUI-writable is the whole point of the module.
  defaultMonitors = ''
    monitor=eDP-1,preferred,0x0,1.33
    monitor=DP-1,preferred,0x-2160,1
    monitor=HDMI-A-1,preferred,-1920x0,1.0
  '';

  defaultWorkspaces = let
    onLaptop = map (n: "workspace=${toString n}, monitor:eDP-1") (lib.range 1 10);
    onExternal = map (n: "workspace=${toString n}, monitor:DP-1") (lib.range 11 20);
  in
    lib.concatStringsSep "\n" (onLaptop ++ onExternal) + "\n";
in {
  # A graphical display arranger, the Hyprland equivalent of macOS's
  # Displays pane: drag monitors into position, set resolution/refresh/scale,
  # then Apply + Save. Save writes ~/.config/hypr/monitors.conf and
  # workspaces.conf, which config.nix sources last so the GUI wins.
  home.packages = [pkgs.nwg-displays];

  # Seed the two files if they are missing, and only then — an existing file is
  # a layout Matt saved from the GUI, and silently regenerating it on every
  # activation would throw that away. This is why they are written from an
  # activation script rather than home.file.
  #
  # Ordering is load-bearing: Home Manager reloads Hyprland from `onFilesChange`
  # as soon as hyprland.conf changes, so seeding must happen BEFORE that or the
  # reload reads a config that sources files which do not exist yet and fails
  # with "source= globbing error: found no match". entryBetween pins it after
  # writeBoundary (files may be written) and before that reload.
  home.activation.seedHyprDisplayConfigs = lib.hm.dag.entryBetween ["onFilesChange"] ["writeBoundary"] ''
    hyprDir="''${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
    $DRY_RUN_CMD mkdir -p "$hyprDir"
    if [ ! -e "$hyprDir/monitors.conf" ]; then
      $DRY_RUN_CMD install -m 0644 ${pkgs.writeText "monitors.conf" defaultMonitors} "$hyprDir/monitors.conf"
    fi
    if [ ! -e "$hyprDir/workspaces.conf" ]; then
      $DRY_RUN_CMD install -m 0644 ${pkgs.writeText "workspaces.conf" defaultWorkspaces} "$hyprDir/workspaces.conf"
    fi
  '';

  # Vicinae (Mod+D) indexes desktop entries, so without this the GUI would be
  # undiscoverable. Named "Displays" because that is what Matt will search for;
  # the file name shadows the entry nwg-displays ships so only one shows up.
  xdg.desktopEntries.nwg-displays = {
    name = "Displays";
    genericName = "Monitor Settings";
    comment = "Arrange monitors, set resolution, refresh rate and scale";
    exec = "nwg-displays";
    icon = "preferences-desktop-display";
    terminal = false;
    type = "Application";
    categories = ["Settings" "HardwareSettings"];
  };
}
