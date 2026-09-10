# Mistakes log

Newest first. Each entry: what went wrong + the fix, so it isn't repeated.

## 2026-06-06 — zen-browser `.override { policies }` doesn't exist on the pinned flake (MAT-572)

**Mistake:** Wired declarative Zen extensions with
`inputs.zen-browser.packages.${system}.default.override { policies = {...}; }`,
copied from the flake's *latest* README. `nixos-rebuild build` failed with
`function 'wrapper' called with unexpected argument 'policies'`.

**Root cause:** In the pinned rev, `default = pkgs.wrapFirefox beta-unwrapped {...}`.
`.override` on `default` therefore exposes **wrapFirefox's** args (no `policies`),
not the unwrapped package's `policies ? {}`. The README example tracks a newer
revision than the lockfile pins.

**Fix:** Re-wrap the same unwrapped derivation `default` is built from, adding
nixpkgs' canonical `extraPolicies`:
`pkgs.wrapFirefox inputs.zen-browser.packages.${system}.beta-unwrapped { icon = "zen-browser"; extraPolicies.ExtensionSettings = {...}; }`.

**Lesson:** Read the *pinned* flake source (`nix flake metadata <url>/<rev>`),
not the upstream README, before using a flake's override interface.
