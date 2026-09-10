# Outstanding: three `path:` flake inputs

## Status

`gdoc-sync-src` is **done** — it now points at its real GitHub remote:

```nix
gdoc-sync-src = {
  url = "git+ssh://git@github.com/MattHandzel/gdoc-sync?ref=main";
  flake = false;
};
```

The other three are still `path:` inputs pointing into `/home/matth/Projects`,
which means **the flake cannot evaluate on a machine that is not this laptop**.
`darwinConfigurations.matts-mac` evaluates here only because those paths exist
here. The Mac will fail at `nix run nix-darwin ... switch` until this is fixed.

## Why it is not done

Creating the three private GitHub repositories was blocked by this agent
session's permission policy, not by a technical problem. `gh auth status`
reports the account is logged in and the token is valid, so the commands below
should succeed when run by hand.

There is one piece of preparation already done: `project-asset-generator` had
two uncommitted working-tree files (a fix that makes `--self-test` work from a
read-only `/nix/store`, plus a `.gitignore` entry for its local `.env`). Those
are committed on the branch **`mac-migration-snapshot`** in that repo, in a
linked worktree at
`/tmp/claude-1000/-home-matth/ebe75412-b158-49ec-8530-a3d8e62bf19f/scratchpad/pag-wt`.
That worktree lives in a scratch directory and will vanish; the branch and its
commit are in the repo itself and are what matters. Clean it up with
`git -C ~/Projects/project-asset-generator worktree prune`.

## What to run

```sh
# 1. project-asset-generator — already a git repo, no remote yet.
#    Fast-forward main onto the prepared commit first, then publish.
cd ~/Projects/project-asset-generator
git worktree prune
git merge --ff-only mac-migration-snapshot
gh repo create MattHandzel/project-asset-generator --private --source=. --push

# 2. SecondBrainSearch — has a CORRUPT .git (objects/ and index only, no HEAD
#    and no config), so git does not see it as a repository at all. `git init`
#    is non-destructive here: it adds the missing HEAD/config and reuses the
#    existing objects directory. qdrant.log is 38 MB of runtime log and must
#    not be committed.
cd ~/Projects/SecondBrainSearch
printf '%s\n' 'qdrant.log' '__pycache__/' '.qdrant-initialized' 'eval/output/' > .gitignore
git init && git add -A && git commit -m 'Initial commit'
gh repo create MattHandzel/SecondBrainSearch --private --source=. --push

# 3. SecondBrainSpeech — not a git repo at all. Its .gitignore already excludes
#    cache/ (61 MB), models/ and *.log, so a plain `git add -A` is safe.
cd ~/Projects/SecondBrainSpeech
git init && git add -A && git commit -m 'Initial commit'
gh repo create MattHandzel/SecondBrainSpeech --private --source=. --push
```

Before pushing each one, confirm nothing sensitive is going up:

```sh
git ls-files | rg -i 'env|secret|token|credential|\.pem$|\.key$'
```

## The repointing diff

Apply to `nixos/.config/nixos/flake.nix`:

```diff
     second-brain-search = {
-      url = "path:/home/matth/Projects/SecondBrainSearch";
+      url = "git+ssh://git@github.com/MattHandzel/SecondBrainSearch?ref=main";
       inputs.nixpkgs.follows = "nixpkgs";
     };
 
     text-to-speech-service = {
-      url = "path:/home/matth/Projects/SecondBrainSpeech";
+      url = "git+ssh://git@github.com/MattHandzel/SecondBrainSpeech?ref=main";
       inputs.nixpkgs.follows = "nixpkgs";
     };
 
     project-asset-generator-src = {
-      url = "path:/home/matth/Projects/project-asset-generator";
+      url = "git+ssh://git@github.com/MattHandzel/project-asset-generator?ref=main";
       flake = false;
     };
```

Then:

```sh
cd ~/dotfiles/nixos/.config/nixos
nix flake lock --update-input second-brain-search \
               --update-input text-to-speech-service \
               --update-input project-asset-generator-src
nix flake metadata --json | jq -r '.locks.nodes | to_entries[] | select(.value.locked.type == "path") | .key'
#   ^ must print nothing. Any output is an input that still cannot resolve off this laptop.
nixos-rebuild build --flake .#laptop     # confirm the laptop is unaffected
```

`project-asset-generator` is referenced only from `linuxPkgs` in
`modules/home/packages.nix` (it needs grim/wtype/hyprland), so it is never
evaluated on the Mac. `second-brain-search` and `text-to-speech-service` are
consumed by NixOS modules only. They still have to *resolve*, though, because
flake inputs are fetched before anything decides whether they are used.

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
