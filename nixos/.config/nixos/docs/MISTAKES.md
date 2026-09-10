# Mistakes (newest first)

## 2026-08-01 — the eval printed STRUCTURAL PASS on zero scored images (MAT-1781)
`harness.py` computed its verdict from summed counters, so when every detection run
crashed the totals were all 0 and it printed `images scored 0/1` followed by
`verdict: STRUCTURAL PASS`. A completely broken detector read as a clean bill of
health. Fix: the verdict now requires `len(ok) == len(results)` and a non-empty
result set, and says outright that the invariants are vacuous otherwise. Lesson: an
"all counters zero" pass condition is indistinguishable from "nothing ran" — make
the check require evidence, not the absence of failures.

## 2026-08-01 — wl-kbptr needs `n < num_symbols` for a one-character label (MAT-1781)
Sized each hierarchy round at `len(symbols)` = 26, expecting one keystroke per round.
`label.c` computes width with `while (n > 0) { len++; n /= num_symbols; }`, so exactly
26 labels over 26 symbols divides to 1 and takes a second pass: every round silently
cost TWO keystrokes. It was invisible in the structural checks — they only saw rounds
of 26, which looked correct — and showed up only as the keystroke mean sitting at 5.5
while the tree got three times shallower. Fix: `one_keystroke_max()` = `len(symbols)-1`,
and the round budget counts the current region, which also occupies a label. Lesson:
when reproducing another program's arithmetic, run its formula on the boundary case;
and when a metric refuses to move after a change that should have moved it, that
disagreement is the bug, not noise.

## 2026-08-01 — three test fixtures that could not exercise what they claimed (MAT-1781)
While building `test_hierarchy.py`: (1) the round-cap fixture used near-identical
boxes, which contain each other, so they were a nested chain rather than the siblings
the cap acts on; (2) the narrowing negative control compared a round against itself,
because the fixture had exactly one top-level region; (3) the shared-prefix control
shuffled paths but kept path LENGTHS, and length correlates with depth and so with
size, so the control came out weakly monotone too and monotonicity alone proved
nothing. Each was caught only by insisting the negative control actually fail. Lesson:
write the failing case first and watch it fail; "the assertion is green" and "the
assertion is testing something" are different claims.

## 2026-08-01 — a leftover key-injector thread typed into the NEXT test (MAT-1781)
`e2e_drilldown.py` starts a thread that types one key per round. When a case consumed
fewer rounds than expected the thread stayed parked waiting for a picker that never
came, then grabbed the next case's picker and sent it a stale `Return` — so the Escape
check came back with a captured region instead of a cancellation, on two runs out of
three. Fix: a stop event, set and joined in a `finally` around each case. Related:
sending a key once after a fixed sleep is a coin flip, because the key is dropped if
it lands before the layer surface has taken its keyboard grab; both e2e scripts now
retry until the picker exits. Lesson: a background driver in a test needs an explicit
lifetime, and timing-based input needs a completion signal, not a sleep.

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
