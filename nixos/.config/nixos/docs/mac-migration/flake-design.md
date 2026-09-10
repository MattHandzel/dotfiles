# nix-darwin host design for ~/dotfiles/nixos/.config/nixos (from Plan agent, 2026-09-09)

## Verified facts that shape the design
- gdoc-sync has a remote (git@github.com:MattHandzel/gdoc-sync.git). project-asset-generator is a git repo with NO remote. SecondBrainSearch and SecondBrainSpeech are NOT git repos. All four are `path:` flake inputs -> flake cannot evaluate on a fresh Mac until fixed.
- pkgs.kanata, aerospace, terminal-notifier, choose-gui, utm, raycast all exist for aarch64-darwin in nixpkgs.
- modules/home/zsh.nix takes an unused `hostname` arg (delete). modules/home/nvim.nix already uses config.home.homeDirectory (portable).
- pkgs/project-asset-generator needs grim/wtype/hyprland -> Linux-only, must not be referenced on darwin.
- modules/home/tmux.nix hardcodes shell=/run/current-system/sw/bin/zsh -> use "${pkgs.zsh}/bin/zsh".
- modules/home/services.nix hardcodes /etc/profiles/per-user/matth/bin/python3 -> use "${pkgs.python3}/bin/python3".
- nixpkgs input is nixos-unstable-small (Linux jobset, ~no darwin binary cache). Add `nixpkgs-darwin = github:NixOS/nixpkgs/nixpkgs-unstable` for the Mac so the first switch downloads instead of compiling texlive/neovim.

## 1. flake.nix
### 1.1 path inputs -> push to GitHub and repoint (do on the laptop, then rebuild laptop, commit)
    gdoc-sync-src = { url = "git+ssh://git@github.com/MattHandzel/gdoc-sync?ref=main"; flake = false; };
    project-asset-generator-src = { url = "git+ssh://git@github.com/MattHandzel/project-asset-generator?ref=main"; flake = false; };   # gh repo create --private --source=. --push first
    second-brain-search = { url = "git+ssh://git@github.com/MattHandzel/SecondBrainSearch?ref=main"; inputs.nixpkgs.follows = "nixpkgs"; };  # git init + gh repo create first
    text-to-speech-service = { url = "git+ssh://git@github.com/MattHandzel/SecondBrainSpeech?ref=main"; inputs.nixpkgs.follows = "nixpkgs"; };
Verify: `nix flake metadata` shows no type:path nodes.

### 1.2 new inputs
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = { url = "github:nix-darwin/nix-darwin/master"; inputs.nixpkgs.follows = "nixpkgs-darwin"; };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = { url = "github:homebrew/homebrew-core"; flake = false; };
    homebrew-cask = { url = "github:homebrew/homebrew-cask"; flake = false; };
    homebrew-bundle = { url = "github:homebrew/homebrew-bundle"; flake = false; };
    nikitabobko-tap = { url = "github:nikitabobko/homebrew-tap"; flake = false; };

### 1.3 outputs
    let username = "matth"; linuxSystem = "x86_64-linux"; darwinSystem = "aarch64-darwin"; sharedVariables = import ./shared_variables.nix; in {
      nixosConfigurations.{desktop,server,laptop,vm} = nixpkgs.lib.nixosSystem { system = linuxSystem; modules = [(import ./hosts/X)]; specialArgs = { host = "X"; inherit self inputs username sharedVariables; }; };
      darwinConfigurations.matts-mac = nix-darwin.lib.darwinSystem { modules = [(import ./hosts/mac)]; specialArgs = { host = "mac"; inherit self inputs username sharedVariables; }; };
      checks = per-system mkChecks (statix/deadnix/alejandra) for both linuxSystem and darwinSystem, using nixpkgs-darwin.legacyPackages for darwin.
    }
host = "mac" (short) because tmux.nix/zsh.nix already branch on `host`.

## 2. Module layout
New files:
    hosts/mac/default.nix                 # nixpkgs.hostPlatform = "aarch64-darwin"; system.stateVersion = 6; system.primaryUser; nix.enable = false (Determinate); imports modules/darwin
    modules/darwin/default.nix            # aggregator
    modules/darwin/system-defaults.nix    # system.defaults.* + system.keyboard + touchIdAuth + fonts
    modules/darwin/homebrew.nix           # nix-homebrew + homebrew.{taps,casks}
    modules/darwin/user.nix               # home-manager wiring (mirror of modules/core/user.nix)
    modules/darwin/sops.nix               # sops-nix darwinModules
    modules/darwin/kanata.nix             # launchd.daemons.kanata
    modules/darwin/packages.nix           # environment.systemPackages (kitty etc. so /Applications/Nix Apps trampoline works)
    modules/shared/kanata-config.nix      # the .kbd text shared verbatim with NixOS
    modules/home/lib/scheduled.nix        # timer/launchd helper
    modules/home/platform.nix             # clip-copy / clip-paste / notify / open-it / pick / type-text shims
    modules/home/linux/mimeapps.nix       # xdg.mimeApps moved out of modules/home/default.nix (Linux-gated option; mkIf cannot save it)
    modules/home/darwin/default.nix       # darwin-only HM aggregator
    modules/home/darwin/aerospace.nix
    modules/home/darwin/compat-shims.nix  # wl-copy/wl-paste/notify-send/xdg-open/wtype/fuzzel by their Linux names -> scripts run unmodified
    modules/home/darwin/zen-config.nix
    modules/home/syncthing.nix            # HM services.syncthing (supports darwin) in SHARED list

modules/home/default.nix:
    let inherit (pkgs.stdenv.hostPlatform) isLinux isDarwin;
        shared = [ theme platform bat btop git kitty nvim starship tmux zsh vscodium packages scripts/scripts services health-dashboard luck-scheduler polish-pipeline gdoc-sync meeting-note-docs linear-notify transcribe-captures predict-ui privacy-card claude-syncthing-ignores todoist syncthing catppuccin ];
        linuxOnly = [ aseprite audacious discord fuzzel gtk hyprland swaync waybar vicinae wispr-flow stuck-key-guard kbd-relay app-memory-caps memwatch electron-app-daily-restart lifelog-collector activitywatch gdrive-mount hm-clobber-guard hm-drift-guard thunderbird foliate readest zen-config linux/mimeapps ];
    in { imports = shared ++ lib.optionals isLinux linuxOnly ++ lib.optionals isDarwin [./darwin]; ... }

Needs-variant modules: btop (nvtop intel linux-only), tmux (shell path), zsh (aliases, open, command-not-found), packages (split shared/linux/darwin lists), scripts (split), services/health-dashboard/luck-scheduler/polish-pipeline/gdoc-sync/meeting-note-docs/linear-notify/transcribe-captures/predict-ui (timers -> scheduled helper), zen-config (profile root).

packages.nix: home.packages = sharedPkgs ++ lib.optionals isLinux linuxPkgs ++ lib.optionals isDarwin darwinPkgs; linuxPkgs gets zenWithExtensions, project-asset-generator, all wl-*/grim/slurp/satty/swayimg/wtype/wlr-randr/gammastep/pwvucontrol/espanso-wayland/logkeys/v4l-utils/ddcutil/gparted/ntfs3g/pika-backup/nwg-look/kdePackages.*/wine*/docker/aw-*/activitywatch/poweralertd/soundwireserver/dialect/crow-translate/wasistlos/wofi-emoji/readest/foliate and every GUI app that becomes a cask.

## 3. scheduled.nix helper (one declaration -> systemd user units on Linux, launchd agent on Darwin)
Signature: scheduled { name; description; command (list, argv0 store path); everySeconds?; onCalendar? (Linux); startCalendarInterval? (Darwin); watchPaths?; keepAlive?; runAtLoad?; restartSec?; persistent?; randomizedDelaySec? (Linux only); path?; environment?; workingDirectory?; logFile?; after? }
Darwin emits launchd.agents.${name}.config = { ProgramArguments; RunAtLoad; ProcessType="Background"; StartInterval|StartCalendarInterval; WatchPaths; KeepAlive={SuccessfulExit=false} + ThrottleInterval when keepAlive; WorkingDirectory; EnvironmentVariables (PATH = makeBinPath path + /usr/bin:/bin:/usr/sbin:/sbin); StandardOutPath/StandardErrorPath }.
Linux emits systemd.user.services/timers/paths exactly as today. `%h` and `%t` are expanded to home / ~/.cache by the helper.
Mapping notes: Type=oneshot+timer -> StartInterval/StartCalendarInterval; Restart=on-failure -> KeepAlive.SuccessfulExit=false; RestartSec -> ThrottleInterval; OnCalendar "*:0/15" -> StartInterval 900; "Sun 19:00" -> [{Weekday=0;Hour=19;Minute=0}]; Persistent implicit; RandomizedDelaySec none (sleep $((RANDOM%120)) in wrapper); paths -> WatchPaths; ConditionPathExists -> guard in script; tmpfiles -> home.file .keep; network-online.target -> retry in script; LaunchAgents get an EMPTY env -> path/environment mandatory.
Worked example gdoc-sync: scheduled { name="gdoc-sync"; command=["${gdoc-sync}/bin/gdoc-sync" "sync" "--all"]; onCalendar="*:0/15"; everySeconds=900; randomizedDelaySec="2m"; after=["network-online.target"]; path=[gdoc-sync pkgs.coreutils]; logFile="%h/.local/state/gdoc-sync.log"; }
second-brain-automation: everySeconds=600 + watchPaths=["%h/notes/capture/raw_capture" "%h/notes/resources"].
luck-scheduler: lib.mkMerge (map (j: scheduled ({workingDirectory="%h/Obsidian/Main"; logFile=...; path=[bash coreutils python3 git];} // j)) [ m1-refresh Sun19:00, sunday-review Sun19:30, now-update Sun19:45, enrich-weekly Tue09:00, parse-capture-poll 300s, drafts-watch 300s, relationships-cache-refresh 06:00, m3-quarterly (launchd cannot express first-Sunday-of-quarter; fire every Sunday 10:00, skill no-ops off-quarter) ]); fix scriptsDir hardcoded /home/matth -> config.home.homeDirectory.

## 4. scripts
platform.nix provides clip-copy (pbcopy|wl-copy), clip-paste (pbpaste/pngpaste|wl-paste), notify (terminal-notifier|notify-send), open-it (open|xdg-open), pick (choose-gui|fuzzel --dmenu), type-text (osascript keystroke|wtype).
compat-shims.nix (darwin only) installs wl-copy/wl-paste/notify-send/xdg-open/wtype/fuzzel names -> ~85 scripts mostly run unmodified.
Shared as-is (~30): compress, extract, tmux-sessionizer, run-nix-shell-on-new-tmux-session, take-note, notify-if-command-is-successful, lifelog-search, glucose, transcribe_captures, TextToSpeechService, claude-ask, send-to-phone-ntfy, pl-assist, pl-capture, ascii, maxfetch, process-log, writing-session, auth-code-watcher, link-search, read-aloud, copy-to-clipboard, smart-clipboard-picker, paste-second-clip, clip2md, grammar-check, password-picker, prompt-picker, screenshot-search, leader-timer, quick-capture.
Linux-only (~35): wall-change, wallpaper-picker, toggle_blur, toggle_oppacity, brightness, secondary-monitor-update, focus_app, switch-workspace-to-other-monitor, run-command-based-on-type-of-workspace, kill-window-and-switch, track_*_history, hyprland-session-*, keybinds, shutdown-script, record, record-lecture, screen-log, kb-lang-status, toggle-stt, wispr-hub, wispr-status, vm-start, runbg, music, lofi, suspend-script-runner, focus-mode-enforcer, focus-distracting-apps, focus-delay-gate, toggle-focus-mode, focus-mode-sync, kbshot, ocr-screenshot, zen-spaces, waybar-agenda, reboot-state.
Darwin variants (~15): audio-log (ffmpeg avfoundation), ocr-screenshot (screencapture -i -x + tesseract), kbshot (screencapture -i), open-website-as-standalone-app (open -na "Google Chrome" --args --app=URL), web-app wrappers mostly deleted in favour of casks (keep Shortwave/Otter), btop-gui/yazi-gui/notetaker (kitty --single-instance --title), ntfy-gui, system-fix (launchctl kickstart), nixos-assistant (darwin-rebuild), reboot-state (osascript restart).
scripts.nix extras: ddcutil/socat/zenity/wl-clipboard/grim/wf-recorder/alsa-utils linux-only; bc/gum/jq/pass/gnupg/nmap/ffmpeg shared. auth-code-watcher + ntfy-desktop-sub -> scheduled {keepAlive=true}; focus-mode-enforcer/sync stay Linux.

## 5. sops
modules/darwin/sops.nix: imports inputs.sops-nix.darwinModules.sops; defaultSopsFile ../../secrets/secrets.yaml; age.sshKeyPaths = ["/Users/${username}/.ssh/id_ed25519"]; secrets gcal_client_secret + linear_api_key owner=username.
/run/secrets on darwin only exists after a reboot (synthetic.conf firmlink). Consumers must use osConfig.sops.secrets.<x>.path (HM is always a submodule here so osConfig exists on both). privacy-card.nix references undeclared privacy_api_key -> declare it or use "${osConfig.sops.defaultSymlinkPath}/privacy_api_key".
Key: copy ~/.ssh/id_ed25519 to the Mac (chosen), or ssh-to-age a new Mac key + sops updatekeys.

## 6. Homebrew (modules/darwin/homebrew.nix)
nix-homebrew { enable; enableRosetta=false; user=username; taps = {homebrew/homebrew-core, homebrew/homebrew-cask, homebrew/homebrew-bundle, nikitabobko/homebrew-tap} from inputs; mutableTaps=false; }
homebrew { enable; onActivation = {autoUpdate=false; upgrade=false; cleanup="zap";}; taps = attrNames nix-homebrew.taps; }
MUST casks: zen-browser, google-chrome, brave-browser, obsidian, slack, beeper, claude, cursor, windsurf, wispr-flow, bitwarden, zoom, discord, raycast, nikitabobko/tap/aerospace, karabiner-elements, orbstack, espanso, activitywatch, google-drive, tailscale-app (verify name), thunderbird.
NICE casks: anki, gimp, libreoffice, obs, calibre, prusaslicer, qbittorrent, utm, aldente, iina, stats, homerow, shottr, jankyborders (tap FelixKratz/formulae), ice.
From nix not cask: kitty, mpv, tailscale CLI, terminal-notifier, choose-gui, kanata. Put GUI nix apps in environment.systemPackages for the /Applications/Nix Apps trampoline.
Syncthing: HM services.syncthing (darwin-capable); do NOT also install the cask (port 8384 fight).

## 7. system defaults (modules/darwin/system-defaults.nix)
system.primaryUser; system.keyboard.{enableKeyMapping, remapCapsLockToEscape}=true; system.startup.chime=false.
NSGlobalDomain: AppleInterfaceStyle="Dark"; AppleShowAllExtensions; AppleShowAllFiles; KeyRepeat=1; InitialKeyRepeat=10; ApplePressAndHoldEnabled=false; NSAutomatic{Capitalization,DashSubstitution,PeriodSubstitution,QuoteSubstitution,SpellingCorrection,InlinePrediction}Enabled=false; NSNavPanelExpandedStateForSaveMode(2)=true; PMPrintingExpandedStateForPrint(2)=true; NSDocumentSaveNewDocumentsToCloud=false; NSWindowResizeTime=0.001; NSWindowShouldDragOnGesture=true; "com.apple.swipescrolldirection"=true (natural ON); "com.apple.keyboard.fnState"=true; "com.apple.mouse.tapBehavior"=1; "com.apple.sound.beep.feedback"=0.
trackpad: Clicking; TrackpadThreeFingerDrag; TrackpadRightClick; ActuationStrength=0.
dock: autohide; autohide-delay=0; autohide-time-modifier=0.15; show-recents=false; static-only=true; mru-spaces=false; launchanim=false; expose-animation-duration=0.1; tilesize=36; orientation="left"; minimize-to-application; wvous-*-corner=1 (all hot corners off).
finder: AppleShowAllFiles; AppleShowAllExtensions; ShowPathbar; ShowStatusBar; _FXShowPosixPathInTitle; FXEnableExtensionChangeWarning=false; FXPreferredViewStyle="Nlsv"; FXDefaultSearchScope="SCcf"; QuitMenuItem; CreateDesktop=false.
screencapture: location=/Users/matth/Pictures/Screenshots; type=png; disable-shadow. (activation mkdir -p that dir.)
spaces.spans-displays=true (AeroSpace wants one space across displays). WindowManager: GloballyEnabled=false (Stage Manager off); EnableStandardClickToShowDesktop=false; StandardHideDesktopIcons.
menuExtraClock Show24Hour/ShowSeconds/ShowDayOfWeek; controlcenter.BatteryShowPercentage; loginwindow.GuestEnabled=false; LaunchServices.LSQuarantine=false; SoftwareUpdate.AutomaticallyInstallMacOSUpdates=false.
security.pam.services.sudo_local.touchIdAuth=true. fonts.packages=[nerd-fonts.jetbrains-mono inter].
Cmd+Space off Spotlight for Raycast: CustomUserPreferences "com.apple.symbolichotkeys".AppleSymbolicHotKeys."64".enabled=false (needs logout) or once in System Settings.

## 8. zsh aliases (darwin branch; delete unused hostname arg)
rebuild = "pushd ~/dotfiles/nixos/.config/nixos && git add --all . && darwin-rebuild switch --flake .#matts-mac && popd"   # NO sudo: nix-darwin elevates itself
rebuildu = same with cp flake.lock backup + nix flake update
hm-switch = nix build .#darwinConfigurations.matts-mac.config.home-manager.users.matth.home.activationPackage -o /tmp/hm-activation-result && HOME_MANAGER_BACKUP_EXT=hm-backup HOME_MANAGER_BACKUP_OVERWRITE=1 /tmp/hm-activation-result/activate
nix-clean = "nix-collect-garbage -d && nix store optimise"; darwin-gens = "darwin-rebuild --list-generations"
Drop open=xdg-open, record, icat on darwin; programs.command-not-found off on darwin; guard command_not_found_handler with optionalString (!isDarwin).

## 9. Bootstrap on the Mac
1. xcode-select --install
2. Determinate Nix: download the installer script from https://install.determinate.systems/nix to a file, review it, then run it with `install --determinate`; then `exec zsh -l`. (Determinate: survives macOS upgrades, has an uninstaller, flakes on; it owns /etc/nix/nix.conf -> nix.enable=false in hosts/mac; substituters go in /etc/nix/nix.custom.conf)
3. ~/.ssh/id_ed25519 in place (also the sops identity); ssh -T git@github.com
4. git clone git@github.com:MattHandzel/dotfiles.git ~/dotfiles
5. sudo mv /etc/zshrc /etc/zshrc.before-nix-darwin; same for /etc/zprofile, /etc/bashrc
6. cd ~/dotfiles/nixos/.config/nixos && nix run nix-darwin/master#darwin-rebuild -- switch --flake .#matts-mac
7. sudo reboot (/run firmlink + Karabiner DriverKit approval)
8. thereafter: rebuild
Gotchas: /etc/nix/nix.conf exists -> nix.enable=false; "Unexpected files in /etc" -> step 5; system.primaryUser required; ids.gids.nixbld=350 only if nix.enable=true; system.stateVersion=6; darwin-rebuild not found -> new shell; never sudo darwin-rebuild; kanata needs Input Monitoring granted to a STABLE path (symlink /usr/local/bin/kanata -> store path) + Karabiner system extension approved + reboot; AeroSpace/espanso/Raycast need Accessibility; terminal-notifier needs Notifications; Intel-only cask -> softwareupdate --install-rosetta.

## kanata on macOS (modules/darwin/kanata.nix)
Extract config text into modules/shared/kanata-config.nix {defcfg; body}. Darwin writes homerow.kbd with defcfg + `macos-dev-names-include ("Apple Internal Keyboard / Trackpad")` and runs launchd.daemons.kanata { ProgramArguments=["${pkgs.kanata}/bin/kanata" "--cfg" cfg "--nodelay"]; RunAtLoad; KeepAlive; logs /var/log/kanata.log }. lmet/rmet = Cmd, lalt/ralt = Option -> homerow ring-finger Super becomes Cmd. (lalt ralt)->f14 still works; bind F14 in Wispr Flow.
Fallback: Karabiner complex modifications.

## Tailscale
Use the GUI app cask (handles NetworkExtension/DNS), keep pkgs.tailscale for CLI, drop nix-darwin services.tailscale. IMPORTANT for Matt: tailnet DNS points at the home server (blocky); with the server down, uncheck "Use Tailscale DNS settings" / `tailscale set --accept-dns=false` or the Mac loses internet.
