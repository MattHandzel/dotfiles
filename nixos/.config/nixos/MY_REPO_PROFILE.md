# Nix Flake Repo Profile (Laptop-Focused)

Scope: this profile treats `hosts/laptop` as the primary target and documents repo-wide patterns that affect it. This is a static audit from reading files; I could not run `nix flake show`/`nix eval` in this environment because connecting to the Nix daemon socket (`/nix/var/nix/daemon-socket/socket`) is blocked.

## A) Executive Summary (10 bullets)

- Flake-based repo (plain `flake.nix`, not flake-parts/devos/snowfall); outputs are **only** `nixosConfigurations.{desktop,laptop,vm}`. `homeConfigurations` is present but commented out in `flake.nix`.
- Laptop host imports `./hosts/laptop/hardware-configuration.nix` plus a monolithic shared module set `./modules/core` (`hosts/laptop/default.nix`).
- Home Manager is integrated as a NixOS module (`inputs.home-manager.nixosModules.home-manager`) and drives most “daily workflow” config via `modules/home/*` (`modules/core/user.nix`).
- System layer enables a fairly broad baseline: Xserver + Hyprland, PipeWire/WirePlumber, printing, netdata, avahi (with firewall openings), geoclue2 location provider, docker/libvirtd virtualization (`modules/core/*`).
- Laptop power stack is aggressive and potentially conflicting: `thermald`, `auto-cpufreq`, and `tlp` enabled together; kernel params include `usbcore.autosuspend=-1` and `mem_sleep_default=s2idle` (`hosts/laptop/default.nix`, `modules/core/bootloader.nix`).
- Security posture is “convenience-first”: passwordless sudo for wheel and explicit `NOPASSWD` for `nixos-rebuild`; user in `docker` group; firewall allows several inbound ports; reverse path filtering disabled (`modules/core/user.nix`, `modules/core/network.nix`).
- Secrets are not managed declaratively (no `sops-nix`/`agenix` found). At least one Home Manager service expects a plaintext JSON in `~/secrets/gcal_client_secret.json` (`modules/home/services.nix`).
- Significant non-declarative automation exists in Home Manager systemd user services (Google Calendar sync with runtime `pip install`, filesystem watchers, personal website sync, focus reminders) (`modules/home/services.nix`).
- Repo contains “workspace detritus” and backups inside the config tree (`.cache/`, `.git.back/`, `.github.back/`, and odd files like `command list-panes: too many arguments (need at most 0)`), which is unusual for a Nix config repo.
- Some config appears internally inconsistent or broken (example: a user timer references `my-user-task.service` but that service is commented out) (`modules/core/bluetooth.nix`).

## B) Repo Structure Map + Explanation

Top-level (key items only; see `find` output for full list):

- `flake.nix`: flake entrypoint, inputs, and `nixosConfigurations`.
- `flake.lock`, `flake.2026-01-10.lock`, `flake.new.lock`: lockfile plus snapshots.
- `hosts/`
  - `hosts/laptop/default.nix`: laptop host manifest (imports hardware + `modules/core`, plus laptop-specific services/power tweaks).
  - `hosts/laptop/hardware-configuration.nix`: generated hardware config (Btrfs root + separate Btrfs `/home`, swapfile).
  - `hosts/laptop/hardware-configuration-yoga.nix`: alternate hardware config (ext4 root); appears archival/variant.
  - `hosts/desktop/*`, `hosts/vm/*`: other targets; VM manifest is notably insecure for SSH (see “Risks”).
- `modules/core/`: system-wide NixOS modules (split by concern; imported as a bundle)
  - `modules/core/default.nix`: aggregator; conditionally imports desktop-only modules; enables geoclue2 + sets `location.provider`.
  - `modules/core/{bootloader,hardware,network,pipewire,program,security,services,system,user,virtualization,wayland,xserver,bluetooth}.nix`
  - `modules/core/overlays/command-not-found.nix`: custom overlay overriding `command-not-found` behavior.
- `modules/home/`: Home Manager modules (app configs, scripts, Wayland desktop, automation)
  - `modules/home/default.nix`: imports many app modules plus Catppuccin HM module.
  - `modules/home/hyprland/*`: Hyprland configuration, variables, lockscreen modules.
  - `modules/home/scripts/`: large personal script suite packaged via HM.
  - `modules/home/services.nix`: HM user services/timers (task sync, watchers, reminders, website sync).
- `pkgs/2048/default.nix`: custom package.
- Root scripts: `install.sh`, `track_window_history.sh`, `track_workspace_history.sh` plus `wallpapers/`.

Module boundary pattern:

- Host files (`hosts/<name>/default.nix`) are thin wrappers around a shared “core” module bundle and per-host overrides.
- Most desktop UX and automation lives in Home Manager (`modules/core/user.nix` imports HM; `modules/home/*` provides content).
- Cross-cutting constants are centralized in `shared_variables.nix` and imported ad-hoc by both system modules and HM modules.

## C) Flake Inputs/Outputs Summary

### Flake type

- Plain flake (no flake-parts): `flake.nix` directly defines `inputs` and `outputs`.

### Inputs (selected)

From `flake.nix`:

- `nixpkgs`: `github:NixOS/nixpkgs/nixos-unstable-small`
- `home-manager`: `github:nix-community/home-manager/master` (follows `nixpkgs`)
- UX/theming: `catppuccin`, `spicetify-nix`, `zen-browser`
- Hyprland tooling: `hypr-contrib`, `hyprpicker`
- Packages/overlays: `nur`, `whisper-overlay`, `nix-gaming`
- Formatting: `alejandra`
- Personal: `lifelog` flake input
- Several commented-out inputs (e.g. custom notion packaging, Hyprland from git, hyprsession).

### Outputs

From `flake.nix`:

- `nixosConfigurations.desktop`: `nixosSystem` with `modules = [(import ./hosts/desktop)]`
- `nixosConfigurations.laptop`: `nixosSystem` with `modules = [(import ./hosts/laptop)]`
- `nixosConfigurations.vm`: `nixosSystem` with `modules = [(import ./hosts/vm)]`

Not present (or commented out):

- `homeConfigurations`: commented out entirely (Home Manager is instead integrated as a NixOS module via `modules/core/user.nix`).
- `packages`, `devShells`, `checks`, `apps`: no explicit outputs defined.

Caching / binary substituters:

- `nix.settings.substituters = ["https://nix-gaming.cachix.org"];` with its key in `modules/core/system.nix`.

## D) Services + Security Inventory Table

Legend:

- State: `on` = enabled, `off` = explicitly disabled, `?` = configured but enable not explicit in the snippet (or is enabled implicitly).
- Layer: `NixOS` (system), `HM` (Home Manager user units).

| Component | Layer | Purpose | State | Relevant Security/Exposure | Source |
|---|---|---|---|---|---|
| `services.xserver` | NixOS | X11 server config + input stack; also used for autologin | on | Autologin enabled for `${username}` | `modules/core/xserver.nix` |
| `services.displayManager.autoLogin` | NixOS | Autologin | on | Convenience vs. physical security | `modules/core/xserver.nix` |
| `programs.hyprland` | NixOS | Hyprland compositor | on | Wayland desktop baseline | `modules/core/wayland.nix` |
| `wayland.windowManager.hyprland` | HM | Hyprland user session config | on | Executes many `exec-once` commands | `modules/home/hyprland/hyprland.nix`, `modules/home/hyprland/config.nix` |
| `xdg.portal` | NixOS | XDG portals for Wayland apps | on | Includes hyprland + gtk portals | `modules/core/wayland.nix` |
| PipeWire + WirePlumber (`services.pipewire.*`) | NixOS | Audio stack | on | `security.rtkit.enable = true` | `modules/core/pipewire.nix`, `modules/core/security.nix` |
| `services.gvfs` | NixOS | GVFS mounts, file manager integration | on | N/A | `modules/core/services.nix` |
| `services.gnome.gnome-keyring` | NixOS | Secret storage; SSH agent via keyring | on | HM sets `SSH_AUTH_SOCK=/run/user/1000/keyring/ssh` | `modules/core/services.nix`, `modules/home/hyprland/variables.nix` |
| `services.dbus` | NixOS | D-Bus system bus | on | N/A | `modules/core/services.nix` |
| `services.fstrim` | NixOS | SSD TRIM timer/service | on | N/A | `modules/core/services.nix` |
| `services.printing` + drivers | NixOS | CUPS printing | on | Network exposure depends on CUPS defaults | `modules/core/services.nix` |
| `services.netdata` | NixOS | Monitoring | on | Potential local/remote UI depending on defaults; firewall not explicitly opened | `modules/core/services.nix` |
| `services.espanso` | NixOS | Text expander | on | Uses `espanso-wayland` package | `modules/core/services.nix` |
| `services.avahi` | NixOS | mDNS / service discovery | on | `openFirewall = true` | `modules/core/services.nix` |
| `services.geoclue2` + `location.provider` | NixOS | Location services | on | Privacy consideration | `modules/core/default.nix` |
| `services.blueman` + `hardware.bluetooth` | NixOS | Bluetooth + tray app | on | Bluetooth policy tweaks; experimental enabled | `modules/core/bluetooth.nix` |
| `systemd.user.services.mpris-proxy` | NixOS (user unit) | Headset media buttons via MPRIS proxy | on | Runs under user session | `modules/core/bluetooth.nix` |
| `systemd.user.timers.my-user-task` | NixOS (user unit) | Daily task timer | on (timer) | Broken: refers to `my-user-task.service` which is commented out | `modules/core/bluetooth.nix` |
| `services.thermald` | NixOS (laptop) | Intel thermal management | on | Power/thermal tuning | `hosts/laptop/default.nix` |
| `services.power-profiles-daemon` | NixOS (laptop) | Power profiles daemon | off | Disabled in favor of auto-cpufreq | `hosts/laptop/default.nix` |
| `services.upower` | NixOS (laptop) | Battery/power reporting; critical actions | on | Critical action set to `Hibernate` | `hosts/laptop/default.nix` |
| `services.auto-cpufreq` | NixOS (laptop) | Dynamic CPU frequency policy | on | May conflict with TLP; charger/battery governors set | `hosts/laptop/default.nix` |
| `services.tlp` | NixOS (laptop) | Power management | on | Battery charge thresholds + USB autosuspend disabled | `hosts/laptop/default.nix` |
| `services.syncthing` | NixOS (laptop) | File sync | on | Stores config in `~/.config/syncthing` | `hosts/laptop/default.nix` |
| `services.fprintd` | NixOS (laptop) | Fingerprint auth daemon | on | PAM integration implications | `hosts/laptop/default.nix` |
| `services.udev.*` | NixOS (laptop) | Udev tooling + rules | on | Disables PCIe wakeup for `pcieport` | `hosts/laptop/default.nix` |
| Docker (`virtualisation.docker`) | NixOS | Containers | on | User in `docker` group (root-equivalent) | `modules/core/services.nix`, `modules/core/virtualization.nix`, `modules/core/user.nix` |
| libvirt (`virtualisation.libvirtd`) | NixOS | QEMU/KVM virtualization | on | Adds user to `libvirtd` group; enables `swtpm` | `modules/core/virtualization.nix` |
| Spice vdagent (`services.spice-vdagentd`) | NixOS | VM integration | on | N/A | `modules/core/virtualization.nix` |
| Steam (`programs.steam`) | HM | Gaming | on | `remotePlay.openFirewall = true` | `modules/home/steam.nix` |
| `systemd.user.services.tw-gcal-sync` + timer | HM | Taskwarrior <-> Google Calendar sync | on | Imperative: creates venv, runs `pip install`, reads `~/secrets/*.json` | `modules/home/services.nix` |
| `systemd.user.services.para-automation-watcher` | HM | Watches notes dir and runs external script | on | Runs out-of-store script in `~/Projects/...` | `modules/home/services.nix` |
| `systemd.user.services.personal-website-sync` + timer | HM | Sync vault to website DB via script | on | Writes logs in `~/Projects/website/`; out-of-store dependency | `modules/home/services.nix` |
| `systemd.user.services.focus-reflection-reminder` + timer | HM | Notification reminder | on | N/A | `modules/home/services.nix` |

Key “security knobs” (system):

- Passwordless sudo for wheel + explicit NOPASSWD for `nixos-rebuild`:
  - `security.sudo.wheelNeedsPassword = false;` and `security.sudo.extraRules` for `/run/current-system/sw/bin/nixos-rebuild` in `modules/core/user.nix`.
- PAM hook for Hyprlock:
  - `security.pam.services.hyprlock = {};` in `modules/core/security.nix`.
- Firewall: enabled, but permissive:
  - `networking.firewall.checkReversePath = false;`
  - Allowed TCP ports include `22`, `80`, `443`, `59010`, `59011`, `8123`, `11434` (and `443` duplicated).
  - Allowed UDP includes `22`, `8000`, `59010`, `59011`, `443`.
  - `services.avahi.openFirewall = true;`
  - Sources: `modules/core/network.nix`, `modules/core/services.nix`, `modules/home/steam.nix`.

## E) Secrets & Credentials Flow Diagram (Textual)

No declarative secrets system detected (no `sops-nix`, `agenix`, `age.secrets`, etc. referenced in `*.nix`).

Current flows observed:

1. Google Calendar sync secret (Home Manager)
   - Secret material location: `~/secrets/gcal_client_secret.json` (expected to exist on disk)
   - Consumption path:
     - `modules/home/services.nix` creates/uses `~/.local/share/tw-gcal-sync/`
     - copies `~/secrets/gcal_client_secret.json` into that directory on first run
     - runs `tw_gcal_sync ... --google-secret ./gcal_client_secret.json`
   - Risk: plaintext secret outside Nix; runtime provisioning; error-prone on fresh machines; not auditable via flake evaluation.

2. “Server IP” as shared variable (not secret, but a credential-adjacent endpoint)
   - Source: `shared_variables.nix: serverIpAddress = "97.223.175.122";`
   - Propagation:
     - Exported as `SERVER_IP_ADDRESS` system env var in `modules/core/system.nix`
     - Also set as HM session variable in `modules/home/hyprland/variables.nix`
     - Used in Zsh helper `transcribe` which curls `http://$SERVER_IP_ADDRESS/v1/audio/transcriptions` in `modules/home/zsh.nix`
   - Risk: no auth/transport security shown (plain HTTP).

3. Commented-out intended secret retrieval
   - `# export TODOIST_API_KEY="$(pass Todoist/API)"` in `modules/home/zsh.nix` suggests a non-Nix secret manager workflow.

## F) Deployment & Update Workflow (Intended)

Repo documentation and embedded workflow hints indicate:

- Primary flake targets: `.#laptop`, `.#desktop`, `.#vm` (`flake.nix`).
- Provisioning helper script:
  - `install.sh` prompts for username/host, copies wallpapers, copies `/etc/nixos/hardware-configuration.nix` into `hosts/<HOST>/hardware-configuration.nix`, then runs `sudo nixos-rebuild switch --flake .#<HOST>`.
  - Note: `install.sh` uses `sed -i` to replace the hardcoded username in `flake.nix` and an Audacious config file.
- Day-to-day rebuild aliases (Home Manager zsh):
  - `rebuild`: `git add --all` then `sudo nixos-rebuild switch --flake <root>.#<host>`
  - `rebuildu`: snapshots `flake.lock` to a dated `flake.YYYY-MM-DD.lock`, runs `sudo nix flake update`, then `sudo nixos-rebuild switch --upgrade ...`
  - Sources: `modules/home/zsh.nix`, `shared_variables.nix` (`rootDirectory`).

## G) Testing/Validation Capabilities

What exists in-repo:

- No explicit flake `checks` output in `flake.nix`.
- No CI workflows in the active tree (there is `.github.back/`, not `.github/`).
- Alejandra is included as an input (`alejandra`), and repo guidelines recommend formatting, but there’s no `nix fmt` wiring shown.

What is intended (per `AGENTS.md`):

- `nix flake show`
- `nix flake check`
- Host closure builds like `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`
- `sudo nixos-rebuild test --flake .#<host>` prior to switch

Audit limitation (this run):

- `nix flake show` failed here due to inability to connect to the Nix daemon socket. On the laptop itself, those commands should be run to confirm evaluation and to catch module option errors (notably the broken user timer).

## H) Eccentricities / Uncommon Patterns (What, Why It Matters, Where)

1. Hardcoded absolute repo path used as a “shared variable”
   - What: `shared_variables.nix` defines `rootDirectory = "/home/matth/dotfiles/nixos/.config/nixos/";`
   - Why it matters: non-portable; breaks if the repo is moved or used by another user; encourages out-of-store references.
   - Where: `shared_variables.nix`, consumed in `modules/home/zsh.nix`, `modules/home/hyprland/variables.nix`, commented systemd hooks in `hosts/laptop/default.nix`.

2. Declarative config mixed with imperative runtime package installs
   - What: HM `tw-gcal-sync` service creates a Python venv and runs `pip install ...` at runtime.
   - Why it matters: nondeterministic; network dependency at runtime; can drift; breaks “reproducible by build” expectations.
   - Where: `modules/home/services.nix`.

3. Broken systemd user timer reference
   - What: `systemd.user.timers.my-user-task` is enabled, but the corresponding `systemd.user.services.my-user-task` is commented out.
   - Why it matters: persistent unit failures; noisy logs; hides real failures.
   - Where: `modules/core/bluetooth.nix`.

4. “Convenience-first” sudo policy
   - What: `security.sudo.wheelNeedsPassword = false` and explicit NOPASSWD rule for `nixos-rebuild`.
   - Why it matters: privilege escalation risk if session is compromised; reduces auditability of privileged actions.
   - Where: `modules/core/user.nix`.

5. Docker enabled in multiple places; user in `docker` group
   - What: docker enabled in `modules/core/services.nix` and `modules/core/virtualization.nix`; user has `extraGroups = [... "docker" ...]`.
   - Why it matters: duplication can mask intent; docker group is effectively root access.
   - Where: `modules/core/services.nix`, `modules/core/virtualization.nix`, `modules/core/user.nix`.

6. Power management “stacking” (auto-cpufreq + TLP + thermald) plus kernel knobs
   - What: enables `services.auto-cpufreq`, `services.tlp`, `services.thermald`, disables `power-profiles-daemon`, sets `usbcore.autosuspend=-1`.
   - Why it matters: competing tuners can fight; `usbcore.autosuspend=-1` can reduce battery life; `mem_sleep_default=s2idle` changes suspend behavior.
   - Where: `hosts/laptop/default.nix`, `modules/core/bootloader.nix`.

7. Hyprland session runs privileged and out-of-store actions on login
   - What: Hyprland `exec-once` includes `sudo chmod 666 /dev/i2c-*` and runs binaries/scripts from `~/Projects/...`.
   - Why it matters: non-declarative dependencies; privilege escalation; fragile across reinstalls; hard to audit/reproduce.
   - Where: `modules/home/hyprland/config.nix`.

8. Custom `command-not-found` overlay that auto-updates `nix-index`
   - What: override adds a zsh handler that runs `nix-index` if cache older than 7 days and optionally runs `thefuck`.
   - Why it matters: unexpected runtime behavior; writes to `~/.cache`; uses `nix-env` in guidance despite flake-first repo; interactive evaluation via `eval`.
   - Where: `modules/core/overlays/command-not-found.nix`.

9. Repo includes `.cache/` and backup directories inside the flake tree
   - What: `.cache/nix/*`, `.git.back/`, `.github.back/`, and stray log/error marker files.
   - Why it matters: adds noise; can accidentally be referenced; makes diffs and audits harder; may leak environment assumptions.
   - Where: repo root listing.

10. VM target is intentionally insecure (worth flagging even though laptop-focused)
   - What: `services.openssh` permits root login and password auth.
   - Why it matters: dangerous if ever exposed beyond localhost/host-only networking.
   - Where: `hosts/vm/default.nix`.

## I) Top 10 Next Improvements (No Implementation)

1. Fix the broken user timer/service pair
   - Rationale: remove guaranteed unit failure noise.
   - Pointer: `modules/core/bluetooth.nix`.

2. Replace `sharedVariables.rootDirectory` absolute path with a robust derivation
   - Rationale: portability; avoids hardcoding `/home/matth/...`.
   - Pointer: `shared_variables.nix`, `modules/home/zsh.nix`, `modules/home/hyprland/variables.nix`.

3. Adopt a declarative secrets mechanism (e.g. `sops-nix` or `agenix`)
   - Rationale: auditability + safe distribution; avoid `~/secrets/*.json` conventions.
   - Pointer: `modules/home/services.nix` (gcal client secret).

4. Remove runtime `pip install` from systemd services; package Python deps in Nix
   - Rationale: reproducibility; offline resilience; faster/cleaner startup.
   - Pointer: `modules/home/services.nix` (`tw-gcal-sync`).

5. Revisit firewall policy and networking hardening
   - Rationale: current allowed ports list is broad; `checkReversePath = false` is a footgun unless justified.
   - Pointer: `modules/core/network.nix`, `modules/core/services.nix`, `modules/home/steam.nix`.

6. Tighten sudo policy
   - Rationale: reduce blast radius; keep NOPASSWD scoped or remove.
   - Pointer: `modules/core/user.nix`, plus the HM aliases in `modules/home/zsh.nix`.

7. Pick a single primary power management approach (or document how conflicts are avoided)
   - Rationale: avoid policy fights between `auto-cpufreq` and `tlp`; align with kernel params.
   - Pointer: `hosts/laptop/default.nix`, `modules/core/bootloader.nix`.

8. Replace `sudo chmod 666 /dev/i2c-*` with udev rules + group membership
   - Rationale: avoids repeated privileged actions and world-writable device nodes.
   - Pointer: `modules/home/hyprland/config.nix`, `modules/core/virtualization.nix` (already adds `i2c` group), and laptop udev hooks in `hosts/laptop/default.nix`.

9. Add flake checks and lightweight evaluation targets
   - Rationale: catch breakages early (like missing systemd units, option typos).
   - Pointer: `flake.nix` (add `checks`), and repo guidelines in `AGENTS.md`.

10. Clean up repo artifacts and add `.gitignore` entries (if appropriate)
   - Rationale: reduce noise and risk of accidentally committing caches/logs/backups.
   - Pointer: `.cache/`, `.git.back/`, `.github.back/`, odd root files; consider `install.sh` behavior and how it edits files.

