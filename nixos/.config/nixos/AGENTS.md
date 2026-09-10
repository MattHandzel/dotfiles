# Repository Guidelines

## Project Structure & Module Organization
This flake is anchored by `flake.nix`, which pins inputs and exposes host systems. Host manifests sit under `hosts/<name>/` (e.g. `hosts/desktop/default.nix`) with matching `hardware-configuration.nix`. Shared modules live in `modules/core` for system-wide knobs, while `modules/home` provides app-specific Home Manager pieces and scripts; keep new modules grouped the same way. Custom packages belong in `pkgs/`, currently featuring `pkgs/2048`. Cross-host constants are managed in `shared_variables.nix`, and helper scripts such as `install.sh`, `track_window_history.sh`, plus wallpapers remain at the repo root for provisioning.

## Build, Test, and Development Commands
- `nix flake show` — confirm the flake evaluates and exported attributes resolve.
- `nix flake check` — run pinned checks; catches syntax issues before a build.
- `nix build .#nixosConfigurations.desktop.config.system.build.toplevel` — create a closure without switching (swap host as needed).
- `sudo nixos-rebuild test --flake .#laptop` — build and activate temporarily for the chosen host.
- `sudo nixos-rebuild switch --flake .#desktop` — deploy the configuration on the target machine.
- Zsh shortcut (`modules/home/zsh.nix`): `rebuild` runs `pushd ~/dotfiles/nixos/.config/nixos && git add --all . && sudo nixos-rebuild switch --flake .#${host} && popd`.

## Home-Manager switches: no permission needed
You may run `hm-switch` (the home-only activation alias in `modules/home/zsh.nix` — builds the HM activationPackage and runs `activate`) yourself WITHOUT asking, to apply changes scoped to `modules/home/**`. It touches only Matt's home generation, not the system, so it is always safe to run. (A full `sudo nixos-rebuild switch` on the system still needs Matt in interactive sessions — hand him that one.)

## Only `switch` survives a reboot — never call a fix "done" after `hm-switch`/`test`
Home Manager runs here as a NixOS module, so `home-manager-matth.service` re-activates the generation baked into the **system** generation at every boot. Only `nixos-rebuild switch` (or `boot`) writes that. Therefore:

- `hm-switch` — applies to the LIVE session only. The next boot silently reverts it.
- `nixos-rebuild test` — same: activates now, leaves the boot default alone.
- `nixos-rebuild switch` — the only durable one.

A reverted change is indistinguishable from a fix that never worked, which is how the Vicinae server unit was "verified working" and then arrived broken after every reboot (2026-07-26: the boot kept re-activating a pre-fix wrapper with no PATH and no `HYPRLAND_INSTANCE_SIGNATURE`). `modules/home/hm-drift-guard.nix` now notifies when a boot reverts a pending `hm-switch`, but the reporting rule is on you:

**Never report a home-module fix as done on the strength of an `hm-switch`/`test` alone.** Prove what a reboot will do without rebooting — build the system and trace the chain:

```
nix build .#nixosConfigurations.laptop.config.system.build.toplevel -o /tmp/laptop-system
rg -o -m1 '/nix/store/\S+-home-manager-generation' /tmp/laptop-system/etc/systemd/system/home-manager-matth.service
# then read <that generation>/home-files/<the unit or file you changed> and confirm it contains the fix
```

Then state plainly that it needs `rebuild` (switch) to persist, and hand Matt that command.

## New features must be launchable from Vicinae (Mod+D) — by default
Whenever you build a new user-facing script, UI, or piece of functionality on the laptop (e.g. the predictions popup), ALSO declare an `xdg.desktopEntries.<name>` entry in the same Home-Manager module, without being asked — Vicinae indexes desktop entries, and Mod+D (`vicinae-toggle`) is how Matt launches things. A feature without a desktop entry is undiscoverable and therefore not done. Follow the existing pattern in `modules/home/scripts/scripts.nix` (`ntfy`, `superhuman`): `name`, `comment`, `exec`, `icon`, `type = "Application"`, `categories`. If the tool needs a terminal, exec it via kitty rather than `Terminal=true` styles that vary by launcher. This does not apply to background services/daemons with no interactive entry point.

## Coding Style & Naming Conventions
Use 2-space indentation and keep attribute names lowercase with hyphenated file names (`hyprland/default.nix`). Format every Nix expression with Alejandra (`nix run github:kamadorueda/alejandra -- .`). Group related options alphabetically and add comments only for non-obvious behavior or upstream overrides.

## Testing Guidelines
Always run `nix flake check` and a host-specific `nixos-rebuild test --flake .#<host>` before pushing. When adjusting packages under `pkgs`, verify them with `nix build .#pkgs.<name>` (or add them to a dev shell for runtime checks). For new host variations, copy the existing `hardware-configuration.nix` pattern and keep module names aligned with their service (`services/hardware.nix`, etc.) so future diffs stay traceable.

## Commit & Pull Request Guidelines
Favor concise, imperative commit subjects (`enable gpu cuda`, `sync home scripts`). Each PR should list affected host(s), the command(s) used to validate (`nixos-rebuild test --flake .#vm`, etc.), and any manual migration steps (secrets, firmware). Reference related issues or todos when available, and include screenshots only for UI or theming updates.

## Security & Configuration Tips
Never commit secrets or tokens; prefer `age`-encrypted files or `environment.etc` references outside version control. Review new flake inputs for license compatibility and pin revisions in `flake.nix`. Periodically prune stale `flake.*.lock` snapshots after major updates to keep evaluation quick.
