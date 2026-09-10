# docs/showcase

Tooling that generates the repo README: screenshots, plus prose harvested from
the modules themselves.

```sh
./showcase.sh scenes                # what can be captured
./showcase.sh capture               # capture every scene
./showcase.sh capture editor shell  # capture named scenes only
./showcase.sh readme                # rewrite README.md from the tree
./showcase.sh readme --check        # exit 1 if the README drifted
./showcase.sh all                   # capture, then rewrite
```

## How the screenshots avoid your session

`hyprctl output create headless` adds a virtual output to the *running*
compositor. `showcase.sh` parks it at x=6000 — far outside any real monitor's
logical extent — and routes every scene window to the workspace bound to it with
a `windowrule` installed before anything launches. Windows tile, render and get
grabbed by `grim` on an output that is never displayed. Focus never moves, the
visible workspace never changes, and the output is removed on exit, on error,
and on Ctrl-C.

That safety rests entirely on the routing rule being accepted, so it is checked
rather than assumed:

- `install_rules` requires `hyprctl` to answer exactly `ok`. Hyprland 0.53
  rejects the older `class:^(x)$` matcher syntax by printing a complaint and
  **exiting 0**, so an unchecked `hyprctl keyword` leaves every scene window free
  to open on top of whatever you are doing. The correct syntax is
  `match:class ^(x)$`, space-separated.
- Every launched window is then confirmed to have landed on the showcase
  workspace. One that didn't is killed immediately and the run aborts.

Headless-*only* Hyprland was tried first and does not work here: with no parent
Wayland socket, aquamarine treats the DRM backend as mandatory, fails to take
DRM master from the live session, and `CBackend::create()` throws. Attaching an
output to the session you already have is the working approach.

## Adding a scene

Drop a file in `scenes/` named `NN-<id>.sh`:

```sh
SCENE_TITLE="Neovim"
SCENE_CAPTION="Shown under the screenshot in the README."
SCENE_SETTLE=6          # seconds to wait before grabbing

scene_run() {
  wallpaper              # repo wallpaper on the virtual output
  bar                    # waybar restricted to the virtual output
  term editor nvim "$CONFIG_ROOT/modules/core/captive-portal.nix"
  settle 1
  term monitor btop      # windows tile in launch order
}
```

Available inside `scene_run`: `term <name> <cmd...>`, `app <name> <cmd...>`,
`bar`, `wallpaper [image]`, `settle [seconds]`, and `$CONFIG_ROOT`.

**Never send keystrokes from a scene.** The virtual output is not focused, so
anything typed lands in the live session instead.

Reference a scene from the README by putting its id in `showcase.toml` — either
`meta.hero` or a highlight's `shot`. Unclaimed scenes land in a gallery section.

## How the prose is generated

`gen_readme.py` writes everything between the `showcase:begin` / `showcase:end`
markers in `../../README.md`. Anything outside the markers is preserved.

- **Generated from the tree**: host list, flake inputs (read from `flake.lock`,
  not regexed out of `flake.nix`), module inventory, unit and script counts, and
  each module's one-line summary.
- **Written by hand**: `showcase.toml` — the framing and the highlights.

Module summaries come from the module's own *docstring*: the comment block at
the top of the file, either on line 1 or immediately after the `{ ... }:` header.
A comment anywhere else describes the line of Nix beneath it, not the module —
lifting those produced summaries like "Add user to libvirtd group" for a file
that does much more. Commented-out Nix, single-line annotations, and heredoc
shebangs are rejected too. A module with no docstring is listed as such rather
than given an invented description, which makes the undocumented list a usable
to-do.

Every `[[highlight]]` in `showcase.toml` names the module paths it describes, and
generation **fails** if one no longer exists — so a renamed module breaks the
build instead of leaving a confident lie in the README.
