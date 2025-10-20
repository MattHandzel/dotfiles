# Repository Guidelines

## Project Structure & Module Organization
This flake is anchored by `flake.nix`, which pins inputs and exposes host systems. Host manifests sit under `hosts/<name>/` (e.g. `hosts/desktop/default.nix`) with matching `hardware-configuration.nix`. Shared modules live in `modules/core` for system-wide knobs, while `modules/home` provides app-specific Home Manager pieces and scripts; keep new modules grouped the same way. Custom packages belong in `pkgs/`, currently featuring `pkgs/2048`. Cross-host constants are managed in `shared_variables.nix`, and helper scripts such as `install.sh`, `track_window_history.sh`, plus wallpapers remain at the repo root for provisioning.

## Build, Test, and Development Commands
- `nix flake show` — confirm the flake evaluates and exported attributes resolve.
- `nix flake check` — run pinned checks; catches syntax issues before a build.
- `nix build .#nixosConfigurations.desktop.config.system.build.toplevel` — create a closure without switching (swap host as needed).
- `sudo nixos-rebuild test --flake .#laptop` — build and activate temporarily for the chosen host.
- `sudo nixos-rebuild switch --flake .#desktop` — deploy the configuration on the target machine.

## Coding Style & Naming Conventions
Use 2-space indentation and keep attribute names lowercase with hyphenated file names (`hyprland/default.nix`). Format every Nix expression with Alejandra (`nix run github:kamadorueda/alejandra -- .`). Group related options alphabetically and add comments only for non-obvious behavior or upstream overrides.

## Testing Guidelines
Always run `nix flake check` and a host-specific `nixos-rebuild test --flake .#<host>` before pushing. When adjusting packages under `pkgs`, verify them with `nix build .#pkgs.<name>` (or add them to a dev shell for runtime checks). For new host variations, copy the existing `hardware-configuration.nix` pattern and keep module names aligned with their service (`services/hardware.nix`, etc.) so future diffs stay traceable.

## Commit & Pull Request Guidelines
Favor concise, imperative commit subjects (`enable gpu cuda`, `sync home scripts`). Each PR should list affected host(s), the command(s) used to validate (`nixos-rebuild test --flake .#vm`, etc.), and any manual migration steps (secrets, firmware). Reference related issues or todos when available, and include screenshots only for UI or theming updates.

## Security & Configuration Tips
Never commit secrets or tokens; prefer `age`-encrypted files or `environment.etc` references outside version control. Review new flake inputs for license compatibility and pin revisions in `flake.nix`. Periodically prune stale `flake.*.lock` snapshots after major updates to keep evaluation quick.
