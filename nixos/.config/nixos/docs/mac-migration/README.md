# Bringing up `matts-mac`

Phase 1 of the NixOS → Mac migration: the flake now has a
`darwinConfigurations.matts-mac` output alongside the four
`nixosConfigurations`. This is the operator's guide for the machine.

The full design rationale is in [flake-design.md](./flake-design.md). Work that
is still outstanding is in [TODO-path-inputs.md](./TODO-path-inputs.md).

## Bootstrap

1. **Xcode command line tools.**

   ```sh
   xcode-select --install
   ```

2. **Nix, via the Determinate installer.** Download the installer to a file,
   read it, then run it. Do not pipe it straight into a shell.

   ```sh
   curl -fsSL -o /tmp/determinate-nix-install https://install.determinate.systems/nix
   less /tmp/determinate-nix-install          # read it before running it
   sh /tmp/determinate-nix-install install --determinate
   exec zsh -l
   ```

   Determinate is chosen because it survives macOS upgrades, ships a real
   uninstaller, and turns flakes on by default. It also **owns
   `/etc/nix/nix.conf`**, which is why `hosts/mac/default.nix` sets
   `nix.enable = false`. Extra substituters go in `/etc/nix/nix.custom.conf`,
   not in the flake.

3. **SSH key.** `~/.ssh/id_ed25519` must be in place before the first switch: it
   is both the git identity and the sops age identity.

   ```sh
   chmod 700 ~/.ssh && chmod 600 ~/.ssh/*
   ssh -T git@github.com
   ```

4. **Clone the flake.**

   ```sh
   git clone git@github.com:MattHandzel/dotfiles.git ~/dotfiles
   cd ~/dotfiles && git switch mac-host
   ```

5. **Move the shell files nix-darwin wants to own.** Skipping this is what
   produces `Unexpected files in /etc` on the first switch.

   ```sh
   sudo mv /etc/zshrc    /etc/zshrc.before-nix-darwin
   sudo mv /etc/zprofile /etc/zprofile.before-nix-darwin
   sudo mv /etc/bashrc   /etc/bashrc.before-nix-darwin
   ```

6. **First switch.** No `sudo` — nix-darwin elevates itself, and
   `sudo darwin-rebuild` leaves root-owned files in `~` that break every later
   switch.

   ```sh
   cd ~/dotfiles/nixos/.config/nixos
   nix run nix-darwin/master#darwin-rebuild -- switch --flake .#matts-mac
   ```

7. **Reboot.** Two things need it: `/run` only exists after the
   `synthetic.conf` firmlink is created (so sops secrets land nowhere useful
   until then), and the Karabiner DriverKit extension is not active until the
   machine has come back up.

8. **From then on** the `rebuild` alias does it:
   `pushd ~/dotfiles/nixos/.config/nixos && git add --all . && darwin-rebuild switch --flake .#matts-mac && popd`

### Gotchas

| Symptom | Cause and fix |
| --- | --- |
| `Unexpected files in /etc` | Step 5 was skipped. |
| `error: system.primaryUser is not set` | Only when `hosts/mac/default.nix` has been edited; it is set there. |
| `darwin-rebuild: command not found` | Open a new shell after the first switch. |
| A cask fails as Intel-only | `softwareupdate --install-rosetta` |
| `ids.gids.nixbld` mismatch | Only applies when `nix.enable = true`. It is `false` here, so ignore it. |
| The Mac loses DNS entirely | The tailnet's resolver is the home server (blocky). While it is down: `tailscale set --accept-dns=false`. |

## macOS permissions checklist

macOS grants these per **binary path**, and every Nix rebuild changes the store
path. `kanata` is therefore run through the stable symlink
`/usr/local/bin/kanata`, which activation re-points at each switch — grant Input
Monitoring to *that* path once and it survives every later rebuild.

Everything below is System Settings → Privacy & Security.

| App | Accessibility | Input Monitoring | Screen Recording | Other |
| --- | --- | --- | --- | --- |
| kanata (`/usr/local/bin/kanata`) | | ✅ | | |
| Karabiner-Elements | | ✅ | | Approve the DriverKit **system extension**, then reboot |
| AeroSpace | ✅ | | | |
| espanso | ✅ | | | |
| Raycast | ✅ | | | |
| Homerow | ✅ | | | |
| The terminal Claude Code runs in | ✅ | ✅ | ✅ | Automation → System Events |
| ActivityWatch | ✅ | | ✅ | |
| Wispr Flow | ✅ | | | Microphone |
| Shottr | | | ✅ | |
| terminal-notifier | | | | Notifications |
| Syncthing | | | | Full Disk Access, if it syncs anything under `~/Library` |

One more that is not a Privacy pane: **Cmd+Space** is freed for Raycast by
`system.defaults` disabling symbolic hotkey 64. macOS only re-reads that at
login, so log out and back in once (or toggle Spotlight's shortcut by hand).

## Keybinding cheatsheet

Option plays the role Super played under Hyprland: Command is load-bearing on
macOS (Cmd+C/V/W/Q/Tab are system-wide), so it cannot be reclaimed. kitty is
told `macos_option_as_alt yes` so Option still arrives as Meta inside tmux and
nvim.

Generated from `modules/home/darwin/aerospace.nix`; regenerate after changing it.

### Focus and move

| Keys | Action |
| --- | --- |
| `alt-h` | focus left |
| `alt-j` | focus down |
| `alt-k` | focus up |
| `alt-l` | focus right |
| `alt-shift-h` | move left |
| `alt-shift-j` | move down |
| `alt-shift-k` | move up |
| `alt-shift-l` | move right |
| `alt-shift-left` | resize width -50 |
| `alt-shift-right` | resize width +50 |
| `alt-shift-up` | resize height -50 |
| `alt-shift-down` | resize height +50 |

### Workspaces

| Keys | Action |
| --- | --- |
| `alt-1` | workspace 1 |
| `alt-2` | workspace 2 |
| `alt-3` | workspace 3 |
| `alt-4` | workspace 4 |
| `alt-5` | workspace 5 |
| `alt-6` | workspace 6 |
| `alt-7` | workspace 7 |
| `alt-8` | workspace 8 |
| `alt-9` | workspace 9 |
| `alt-0` | workspace 10 |
| `alt-ctrl-1` | workspace 11 |
| `alt-ctrl-2` | workspace 12 |
| `alt-ctrl-3` | workspace 13 |
| `alt-ctrl-4` | workspace 14 |
| `alt-ctrl-5` | workspace 15 |
| `alt-ctrl-6` | workspace 16 |
| `alt-ctrl-7` | workspace 17 |
| `alt-ctrl-8` | workspace 18 |
| `alt-ctrl-9` | workspace 19 |
| `alt-ctrl-0` | workspace 20 |
| `alt-shift-1` | move-node-to-workspace 1 |
| `alt-shift-2` | move-node-to-workspace 2 |
| `alt-shift-3` | move-node-to-workspace 3 |
| `alt-shift-4` | move-node-to-workspace 4 |
| `alt-shift-5` | move-node-to-workspace 5 |
| `alt-shift-6` | move-node-to-workspace 6 |
| `alt-shift-7` | move-node-to-workspace 7 |
| `alt-shift-8` | move-node-to-workspace 8 |
| `alt-shift-9` | move-node-to-workspace 9 |
| `alt-shift-0` | move-node-to-workspace 10 |
| `alt-tab` | workspace-back-and-forth |

### Window control

| Keys | Action |
| --- | --- |
| `alt-q` | close |
| `alt-f` | fullscreen |
| `alt-space` | layout floating tiling |
| `alt-s` | layout tiles horizontal vertical |

### Launchers

| Keys | Action |
| --- | --- |
| `alt-t` | exec-and-forget open -na kitty --args -e tmux -L hypr new-session |
| `alt-shift-t` | layout floating then exec-and-forget open -na kitty |
| `alt-b` | exec-and-forget open -a "Zen" |
| `alt-d` | exec-and-forget open -a Raycast |
| `alt-e` | exec-and-forget open -g "raycast://extensions/raycast/emoji-symbols/search-emoji-symbols" |
| `alt-v` | exec-and-forget open -g "raycast://extensions/raycast/clipboard-history/clipboard-history" |
| `alt-x` | exec-and-forget password-picker |

### Modes

| Keys | Action |
| --- | --- |
| `alt-shift-space` | mode leader |
| `alt-g` | mode translate |
| `alt-shift-g` | mode translate-alt |

### App hotkeys (`alt-ctrl-<letter>`)

| Keys | Action |
| --- | --- |
| `alt-ctrl-a` | exec-and-forget open -a "Anki" |
| `alt-ctrl-b` | exec-and-forget open -na kitty --args --title btop -e btop |
| `alt-ctrl-c` | exec-and-forget open -a "Google Calendar" |
| `alt-ctrl-d` | exec-and-forget open -a "Discord" |
| `alt-ctrl-e` | exec-and-forget open -a "Finder" |
| `alt-ctrl-f` | exec-and-forget open -na kitty --args --title yazi -e yazi |
| `alt-ctrl-g` | exec-and-forget open -a "GIMP" |
| `alt-ctrl-h` | exec-and-forget open -a "Beeper" |
| `alt-ctrl-i` | exec-and-forget open -a "WhatsApp" |
| `alt-ctrl-k` | exec-and-forget open -a "Slack" |
| `alt-ctrl-l` | exec-and-forget open -a "Linear" |
| `alt-ctrl-m` | exec-and-forget open -a "Superhuman" |
| `alt-ctrl-n` | exec-and-forget open -na kitty --args --title notetaker -e nvim /Users/matth/Obsidian/Main |
| `alt-ctrl-o` | exec-and-forget open -a "Obsidian" |
| `alt-ctrl-p` | exec-and-forget open -a "PrusaSlicer" |
| `alt-ctrl-r` | exec-and-forget open -a "Raycast" |
| `alt-ctrl-s` | exec-and-forget open -a "Spotify" |
| `alt-ctrl-t` | exec-and-forget open -a "Tasker" |
| `alt-ctrl-u` | exec-and-forget open -a "UltiMaker Cura" |
| `alt-ctrl-w` | exec-and-forget open -a "Wispr Flow" |
| `alt-ctrl-y` | exec-and-forget open -a "Gemini" |
| `alt-ctrl-z` | exec-and-forget open -a "Zoom" |

### Leader mode (`alt-shift-space`, then)

| Keys | Action |
| --- | --- |
| `1` | exec-and-forget leader-timer 1 then mode main |
| `2` | exec-and-forget leader-timer 2 then mode main |
| `3` | exec-and-forget leader-timer 3 then mode main |
| `4` | exec-and-forget leader-timer 4 then mode main |
| `5` | exec-and-forget leader-timer 5 then mode main |
| `6` | exec-and-forget leader-timer 6 then mode main |
| `7` | exec-and-forget leader-timer 7 then mode main |
| `8` | exec-and-forget leader-timer 8 then mode main |
| `9` | exec-and-forget leader-timer 9 then mode main |
| `0` | exec-and-forget leader-timer 10 then mode main |
| `esc` | mode main |

### Translate modes (`alt-g` / `alt-shift-g`, then `enter`)

| Keys | Action |
| --- | --- |
| `translate` + `enter` | exec-and-forget open -g "raycast://extensions/raycast/translator/translate" then mode main |
| `translate` + `esc` | mode main |
| `translate-alt` + `enter` | exec-and-forget open -g "raycast://extensions/raycast/translator/translate?fallbackText=" then mode main |
| `translate-alt` + `esc` | mode main |
