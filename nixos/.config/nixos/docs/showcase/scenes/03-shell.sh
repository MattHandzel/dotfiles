# The terminal: prompt, listings, and the flake itself.
#
# Each pane ends in `exec zsh -i` so the real Starship prompt is left on screen.
# Nothing is typed — the scene must never touch the keyboard, because the
# showcase output is not focused and keystrokes would land on the live session.

SCENE_TITLE="The shell"
SCENE_CAPTION="Zsh + Starship + Atuin, with eza, bat, duf and procs standing in for the coreutils."
SCENE_SETTLE=5

scene_run() {
  wallpaper

  term tree zsh -ic "cd '$CONFIG_ROOT' && eza --tree --level=2 --icons --group-directories-first modules; exec zsh -i"
  settle 1
  term disks zsh -ic 'duf --only local 2>/dev/null || df -h; exec zsh -i'
}
