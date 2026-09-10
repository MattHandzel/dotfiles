# SketchyBar — the status bar that replaces waybar on the Mac.
#
# The bar itself is a Homebrew formula (FelixKratz/formulae/sketchybar, see
# modules/darwin/homebrew.nix) because it needs to be a signed, non-sandboxed
# .app-less binary that macOS lets draw over the notch strip. The CONFIG is
# ours and lives here: ./sketchybar/{sketchybarrc,colors.sh,plugins/} is linked
# to ~/.config/sketchybar verbatim, so the files read the same on disk as in
# the repo and `sketchybar --reload` picks up an edit without a switch.
#
# What it shows, left → right (Catppuccin Mocha, JetBrainsMono Nerd Font):
#   AeroSpace workspaces (focused = Mauve pill, app glyphs per workspace)
#   front app + window title
#   ─ centre ─ clock `EEE d MMM  HH:mm` · today's next calendar event
#   ─ right  ─ cpu · memory · battery · wifi · volume · tailscale dot
#
# AeroSpace pushes workspace changes with `exec-on-workspace-change` (see
# aerospace.nix); everything else polls on a slow timer or subscribes to a
# SketchyBar system event.
#
# plugins/icon_map.sh is vendored from
#   https://github.com/kvndrsslr/sketchybar-app-font/releases (icon_map.sh)
# and pairs with the `font-sketchybar-app-font` cask. Refresh both together.
#
# The macOS menu bar is set to auto-hide (NSGlobalDomain _HideMenuBar, in
# system-defaults.nix) so this is THE bar; Ice only governs what appears when
# the native bar is summoned by hovering the top edge.
{
  config,
  lib,
  pkgs,
  ...
}: let
  home = config.home.homeDirectory;
  sketchybar = "/opt/homebrew/bin/sketchybar";
in {
  xdg.configFile."sketchybar" = {
    source = ./sketchybar;
    recursive = true;
  };

  # The launchd agent. Same shape as what `brew services start sketchybar`
  # writes, but owned by the flake. KeepAlive restarts it if it ever dies;
  # ProcessType Interactive keeps it snappy under load.
  launchd.agents.sketchybar = {
    enable = true;
    config = {
      ProgramArguments = [sketchybar];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Interactive";
      Nice = -20;
      EnvironmentVariables = {
        # LaunchAgents start with no PATH. The plugins use absolute paths for
        # everything system-side; this covers `open`, brew CLIs and Nix tools.
        PATH = lib.concatStringsSep ":" [
          "/opt/homebrew/bin"
          "${home}/.nix-profile/bin"
          "/run/current-system/sw/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
        LANG = "en_US.UTF-8";
      };
      StandardOutPath = "${home}/.local/state/sketchybar.log";
      StandardErrorPath = "${home}/.local/state/sketchybar.err.log";
    };
  };

  # The first day on the Mac the bar was started with `brew services start
  # sketchybar` (label sh.brew.sketchybar) so it was live before this module
  # was ever switched in. Two agents would mean two bars, so once this one
  # exists the brew one is stopped. Idempotent: does nothing when the brew
  # plist is absent.
  home.activation.retireBrewSketchybar = lib.hm.dag.entryAfter ["writeBoundary"] ''
    brewPlist="${home}/Library/LaunchAgents/sh.brew.sketchybar.plist"
    if [ -f "$brewPlist" ] && [ -x /opt/homebrew/bin/brew ]; then
      $VERBOSE_ECHO "sketchybar: retiring the brew-services agent in favour of the flake one"
      $DRY_RUN_CMD /opt/homebrew/bin/brew services stop sketchybar >/dev/null 2>&1 || true
    fi
  '';

  # Hot-reload the running bar after every switch so a config edit shows up
  # without touching launchd.
  home.activation.reloadSketchybar = lib.hm.dag.entryAfter ["retireBrewSketchybar"] ''
    if [ -x ${sketchybar} ] && /usr/bin/pgrep -q -x sketchybar; then
      $DRY_RUN_CMD ${sketchybar} --reload >/dev/null 2>&1 || true
    fi
  '';
}
