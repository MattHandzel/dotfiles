# Mistakes log (NixOS flake)

Newest first. Each entry: what broke, root cause, fix — so it gets fixed once, not repeated.

## 2026-06-27 — jq object construction with `empty` produces NO output (MAT-1198)
**What:** the nameplate listener's `current.json` came out 0 bytes whenever the badge had no QR (the common case). The PNG published fine; only the JSON was empty.
**Cause:** the jq builder used `{ …, qr_target: ($qr | select(. != "")), … }`. When `$qr` is empty, `select(…)` yields the empty stream, and jq's object construction takes the *cartesian product* of its value streams — so one `empty` value collapses the WHOLE object to zero outputs. jq exits 0 having printed nothing.
**Fix:** never let a value expression yield `empty` inside `{…}`. Use `qr_target: (if $qr == "" then null else $qr end)` so the field is always present (null or string). Lesson: inside jq object/array literals, map "absent" to an explicit `null`, not `empty`.

## 2026-06-27 — PIL infers image format from the file EXTENSION, so temp files need `.png` (MAT-1198)
**What:** the listener's atomic-publish wrote the render to a `mktemp` temp file then renamed it into place; render.py crashed with `ValueError: unknown file extension: .twkkkq`.
**Cause:** `mktemp "$dir/.current.png.XXXXXX"` puts the random chars LAST, so the path ends in `.twkkkq`, not `.png`. PIL's `Image.save(path)` picks the encoder from the trailing extension — an unknown ext is fatal.
**Fix:** `mktemp --suffix=.png "$dir/.current-XXXXXX"` (and `--suffix=.json`) so the temp file keeps a real extension; the atomic `mv` into `current.png` is unchanged. Lesson: when a tool infers type from the extension, temp/staging files must carry that extension.

## 2026-06-27 — render.py font lookup globs ALL of /nix/store when its pinned path is absent (MAT-1198)
**What:** every badge render hung for minutes on the server; a 4-minute timeout fired before any PNG appeared.
**Cause:** `render.py` (MAT-1113) hard-codes ONE DejaVu store path, then on a miss falls back to `glob.glob("/nix/store/**/DejaVuSans-Bold.ttf", recursive=True)` — walking the entire store. The pinned path didn't exist on this host (different nixpkgs), and `render.py` is re-invoked as a fresh subprocess per message, so it re-globbed every time.
**Fix:** added a `NAMEPLATE_FONT` env override as render.py's first font candidate (returns immediately, no glob); the `nameplate-listener.nix` module sets it to `${pkgs.dejavu_fonts}/…/DejaVuSans-Bold.ttf`. Real render latency dropped from a multi-minute hang to ~instant (full claude→render→publish is ~11s, claude-dominated). Lesson: a fallback that scans /nix/store is a latency landmine — always give the hot path an explicit, pinned input.

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
