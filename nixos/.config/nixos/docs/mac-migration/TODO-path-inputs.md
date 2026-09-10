# Flake inputs: DONE

All four project inputs are real git remotes; `nix flake metadata` reports no
`type:path` nodes, which is what makes this flake evaluable on the Mac.

| Input | URL |
| --- | --- |
| `gdoc-sync-src` | `git+ssh://git@github.com/MattHandzel/gdoc-sync?ref=main` |
| `project-asset-generator-src` | `git+ssh://git@github.com/MattHandzel/project-asset-generator?ref=main` |
| `second-brain-search` | `git+ssh://git@github.com/MattHandzel/SecondBrainSearch?ref=main` |
| `text-to-speech-service` | `git+ssh://git@github.com/MattHandzel/SecondBrainSpeech?ref=main` |

Three private repositories were created for this. Two notes on them:

- **SecondBrainSearch** had a corrupt `.git` (an objects directory and a stale
  index, no HEAD and no config), so git did not see it as a repository at all.
  `git init` reused the existing objects non-destructively and the stale index
  was cleared before staging. History therefore starts fresh at `478293d`.
  `qdrant.log` (38 MB of runtime log) is gitignored, along with `__pycache__`,
  `.venv`, `storage/` and `eval/output/`.
- **SecondBrainSpeech** was not a repository at all. Its existing `.gitignore`
  already excluded `cache/` (61 MB), `models/` and `*.log`, so nothing large or
  secret went up. History starts at `69860ca`.
- **project-asset-generator** already had history. Its remote `main` is
  `c569220`, which is the previous `main` plus one commit carrying the two
  files that were sitting uncommitted in the working tree (a fix that makes
  `--self-test` work from a read-only `/nix/store`, and a `.gitignore` entry for
  the local `.env`). The LOCAL `main` is still one commit behind at `7367f2e`
  with those same changes uncommitted, because the fleet worktree guard blocks
  `git commit` in a primary checkout. To reconcile:

  ```sh
  cd ~/Projects/project-asset-generator
  git worktree prune
  git merge --ff-only mac-migration-snapshot   # local main catches up; tree goes clean
  ```

  Every staged file set was scanned for `env|secret|token|credential|.pem|.key`
  before pushing; no matches in any of the three.

# Also outstanding

## Darwin variants of ~15 scripts

`modules/home/scripts/scripts.nix` now splits into `sharedScripts` (28, which
run unmodified on macOS via the compat shims) and `linuxScripts` (49, gated
out of the darwin build). The design lists about fifteen of those Linux ones as
wanting a macOS rewrite rather than simply being dropped:

`audio-log` (ffmpeg avfoundation), `ocr-screenshot` (`screencapture -i -x` +
tesseract), `kbshot` (`screencapture -i`), `open-website-as-standalone-app`
(`open -na "Google Chrome" --args --app=URL`), `system-fix`
(`launchctl kickstart`), `nixos-assistant` (`darwin-rebuild`), `reboot-state`
(osascript restart), `ntfy-gui`, and the `btop-gui` / `yazi-gui` / `notetaker`
kitty wrappers.

The three kitty wrappers are already covered without new scripts —
`alt-ctrl-b`, `alt-ctrl-f` and `alt-ctrl-n` in the AeroSpace config launch
kitty directly. The rest are Phase 6 work, to be written **on the Mac** where
they can actually be run; writing them blind from Linux would be unverifiable.

## Cross-platform evaluation limit

`nix eval .#darwinConfigurations.matts-mac.config.system.build.toplevel.drvPath`
cannot complete on x86_64-linux. It is not a problem with this configuration:
`catppuccin`'s starship module does import-from-derivation on a
`catppuccin-starship` derivation whose install hook is `aarch64-darwin`, and a
Linux machine has no way to build it. Everything up to that point evaluates.
The reachable gates are in the Phase 1 report, and the real check is the first
`darwin-rebuild switch` on the Mac.
