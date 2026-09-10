# The hero shot: bar, wallpaper, and a real tiled workspace.
#
# A scene file sets SCENE_TITLE / SCENE_CAPTION / SCENE_SETTLE and defines
# scene_run(). Inside scene_run() you have: bar, wallpaper, term, app, settle.
# Windows tile in launch order, so launch left-to-right.

SCENE_TITLE="The desktop"
SCENE_CAPTION="Hyprland with Waybar, Catppuccin Mocha throughout — Neovim on a system module, btop, and the shell."
SCENE_SETTLE=5

scene_run() {
  wallpaper
  bar

  term editor nvim "$CONFIG_ROOT/modules/core/captive-portal.nix"
  settle 1
  term monitor btop
  settle 1
  term shell zsh -ic 'fastfetch 2>/dev/null || maxfetch; exec zsh -i'
}
