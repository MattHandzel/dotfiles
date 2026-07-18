# Mistakes (newest first)

## 2026-07-18 — home-manager user service that shells out needs explicit PATH (MAT-1462)
`aw-watcher-window-hyprland` shells out to `hyprctl activewindow -j` every poll. As a
home-manager `systemd.user.services` unit it inherited a minimal PATH without `hyprctl`,
so it silently logged "Failed to get active window" and posted zero events (buckets were
created, but `last_updated` stayed null — easy to mistake for "working"). Fix: set
`Service.Environment = ["PATH=${pkgs.lib.makeBinPath [pkgs.hyprland pkgs.coreutils]}"]`
(same guard `wispr-pill-follow` already uses). Lesson: any user unit that execs a helper
binary must put that binary on PATH explicitly — don't rely on the session/manager PATH.

## 2026-07-18 — flake `nixos-rebuild build` can't see an untracked new module (MAT-1462)
Added `modules/home/activitywatch.nix` and imported it, but `nixos-rebuild build --flake`
failed with `path '.../activitywatch.nix' does not exist`. Flakes copy only git-tracked
files into the store; a brand-new untracked file is invisible even with a dirty tree.
Fix: `git add modules/home/activitywatch.nix` (path-scoped) before building.

## 2026-07-18 — `pkill -f` matched the wrapping shell (MAT-1462)
`pkill -f 'sh -c aw-watcher-afk'` matched the harness's own `sh -c ...` wrapper and killed
the running command (exit 144). Fix: kill by explicit PID; never use a `pkill -f` pattern
broad enough to match the wrapping shell.
