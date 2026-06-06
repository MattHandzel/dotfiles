# Mistakes log (NixOS flake)

Newest first. Each entry: what broke, root cause, fix — so it gets fixed once, not repeated.

## 2026-06-06 — a new `.nix` file is invisible to the flake until `git add` (MAT-565)
**What:** added `modules/home/nvim-url-handler.nix` and imported it from `modules/home/default.nix`,
then `nixos-rebuild build --flake .#laptop` failed with
`error: path '/nix/store/…-source/…/modules/home/nvim-url-handler.nix' does not exist`.
**Cause:** Nix flakes build from the git tree and **only see git-TRACKED files**. An untracked
(new, never `git add`ed) file is excluded from the source copied to the store, even though it sits
right there in the working dir. Modified-but-tracked files ARE seen (their dirty working-tree content
is used), which is why edits to existing files worked but the brand-new file 404'd.
**Fix:** `git add modules/home/nvim-url-handler.nix` (path-scoped — never `git add .`) BEFORE the
flake build/eval. Lesson: after creating any new file a flake imports, stage it immediately.

## 2026-06-06 — the agent harness "Bash" shell is NOT bash; bashisms misbehave (MAT-565)
**What:** unit-testing the `nvim-open` script's URL-decode logic (`${path//%/\\x}` + `printf '%b'`)
in the harness shell produced wrong output — `%20` was left undecoded and a stray NUL/space appeared.
**Cause:** the harness Bash tool runs commands under a shell where `$BASH_VERSION` is EMPTY (a
non-bash `sh`/POSIX shell), so bash-only parameter-expansion replacement and `printf '%b'` hex escapes
don't behave as in bash. The shipped script is fine — `pkgs.writeShellApplication` runs it under real
`#!/usr/bin/env bash`.
**Fix:** when validating a bash script's logic from the harness, run it under explicit `bash -c '…'`
(GNU bash 5.x), not the default tool shell. Re-running under `bash -c` confirmed the logic was correct.
