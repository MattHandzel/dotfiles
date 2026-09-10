# Neovim, full-bleed, on a module that is worth reading.

SCENE_TITLE="Neovim"
SCENE_CAPTION="The editor config, opened on the captive-portal module — one of the many places this repo writes down *why* rather than just *what*."
SCENE_SETTLE=6

scene_run() {
  wallpaper
  term editor nvim "$CONFIG_ROOT/modules/core/captive-portal.nix"
}
