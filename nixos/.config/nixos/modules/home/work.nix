# The Redwood-issued MacBook's Home Manager profile: how Matt works, with none
# of what he knows. It gets the core settings (./core.nix), the window and
# keyboard setup, and the command-line tools the shell config calls. It gets
# no lifelog and no secrets; the Redwood notes and work-safe Claude setup
# arrive through claude-config-sync below.
#
# Design and reasons: the vault note
# projects/generator-residency/ai-uplift-for-ai-safety/redwood-two-laptop-design-2026-11-23.md
# App settings that live outside Nix travel in the kit (scripts/redwood-kit).
{
  pkgs,
  lib,
  config,
  ...
}: let
  genericScripts = [
    "calendar"
    "superhuman"
    "linear"
    "zoom-web"
    "claude.ai"
    "com.anthropic.Claude"
    "open-website-as-standalone-app"
    "maxfetch"
    "compress"
    "extract"
    "ascii"
    "tmux-sessionizer"
    "run-nix-shell-on-new-tmux-session"
    "notify-if-command-is-successful"
    "copy-to-clipboard"
    "clip2md"
    "screenshot-search"
    "leader-timer"
    "focus_app"
    "brightness"
    "switch-workspace-to-other-monitor"
    "run-command-based-on-type-of-workspace"
    "kill-window-and-switch"
    "btop-gui"
    "yazi-gui"
    "runbg"
    "lofi"
    "take-note"
    "grammar-check"
    "paste-second-clip"
    "notetaker"
    "toggle-stt"
    "smart-clipboard-picker"
    "screenshot-search"
    "shutdown-script"
    "wallpaper-picker"
    "wall-change"
    # Focus Mode (Matt, 2026-11-27: "the focused mode scripts, timers ... that's
    # not been synchronized to my work laptop"). The Raycast "Toggle Focus Mode"
    # command shipped on 11-24 without these, so it did nothing here.
    "toggle-focus-mode"
    "focus-distracting-apps"
    "focus-delay-gate"
    "quick-capture" # Raycast "Quick Capture": text/clipboard/audio/screenshot into ~/notes
    "lid-awake"
  ];
  ocrScreenshot = import ./scripts/scripts/ocr-screenshot/default.nix {inherit pkgs;};
  # Claude Code setup from the personal Mac (Matt, 2026-11-24: "the same skills,
  # context when I'm doing anything work related"). The personal Mac's
  # scripts/claude-work-sync builds a private repo, MattHandzel/claude-work-config,
  # with the work-safe skills, agents, a CLAUDE-matt.md and his Redwood notes;
  # this pulls it with a read-only deploy key every 15 min. Skills/agents are
  # linked into ~/.claude without replacing anything already there (Redwood's own
  # skills win), ~/.claude/CLAUDE.md imports CLAUDE-matt.md, and the notes are
  # copied into ~/Obsidian/Main (no deletes, so notes written here stay).
  claudeConfigSync = let
    script = pkgs.writeShellScript "claude-config-sync" ''
      set -u
      export PATH=${lib.makeBinPath [pkgs.git pkgs.coreutils pkgs.rsync pkgs.openssh pkgs.gnugrep]}:/usr/bin:/bin
      export GIT_SSH_COMMAND="ssh -i $HOME/.ssh/claude_work_config -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
      repo="$HOME/claude-work-config"
      if [ ! -d "$repo/.git" ]; then
        git clone -q git@github.com:MattHandzel/claude-work-config.git "$repo" || exit 1
      fi
      git -C "$repo" pull -q --ff-only origin main || exit 1
      mkdir -p "$HOME/.claude/skills" "$HOME/.claude/agents" "$HOME/Obsidian/Main"
      for d in "$repo"/skills/*/; do
        n=$(basename "$d"); t="$HOME/.claude/skills/$n"
        [ -e "$t" ] && [ ! -L "$t" ] && continue
        ln -sfn "$d" "$t"
      done
      for f in "$repo"/agents/*.md; do
        t="$HOME/.claude/agents/$(basename "$f")"
        [ -e "$t" ] && [ ! -L "$t" ] && continue
        ln -sfn "$f" "$t"
      done
      for t in "$HOME"/.claude/skills/* "$HOME"/.claude/agents/*; do
        [ -L "$t" ] && [ ! -e "$t" ] && rm -f "$t"
      done
      line="@$repo/CLAUDE-matt.md"
      touch "$HOME/.claude/CLAUDE.md"
      grep -qxF "$line" "$HOME/.claude/CLAUDE.md" || printf '\n# Matt: own instructions, synced from his personal Mac\n%s\n' "$line" >> "$HOME/.claude/CLAUDE.md"
      rsync -a "$repo/context/" "$HOME/Obsidian/Main/"
      # The same Redwood notes (meetings, people, project files) inside the work
      # vault too, so they show up there (Matt, 2026-11-25: "In the work folder, I
      # only see templates"). A copy that each pass refreshes from matts-mac: edits
      # here are overwritten, and none of it syncs back (no classification: AL1).
      mkdir -p "$HOME/Obsidian/Work/redwood"
      rsync -a "$repo/context/" "$HOME/Obsidian/Work/redwood/"
      printf '%s\n' "Copied from Matt's personal Mac by claude-config-sync every 15 min." "Edits here are overwritten; write new notes elsewhere in ~/Obsidian/Work." > "$HOME/Obsidian/Work/redwood/README.md"
      echo "$(date -Iseconds) ok $(git -C "$repo" rev-parse --short HEAD)"
    '';
  in {
    enable = true;
    config = {
      ProgramArguments = ["${script}"];
      StartInterval = 900;
      RunAtLoad = true;
      StandardOutPath = "/Users/matth/.local/state/claude-config-sync.log";
      StandardErrorPath = "/Users/matth/.local/state/claude-config-sync.err.log";
    };
  };
  dotfilesSync = let
    script = pkgs.writeShellScript "dotfiles-sync" ''
      set -u
      export PATH=${lib.makeBinPath [pkgs.git pkgs.coreutils]}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin
      repo="$HOME/dotfiles"
      branch="''${DOTFILES_BRANCH:-$(git -C "$repo" rev-parse --abbrev-ref HEAD)}"
      notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Dotfiles sync\""; }
      before=$(git -C "$repo" rev-parse HEAD) || exit 1
      if ! git -C "$repo" fetch -q origin "$branch" || ! git -C "$repo" merge -q --ff-only FETCH_HEAD; then
        echo "$(date -Iseconds) pull failed (local edits or diverged history in $repo?)" >&2
        notify "Pull failed: check ~/dotfiles (local edits?)"
        exit 1
      fi
      after=$(git -C "$repo" rev-parse HEAD)
      echo "$(date -Iseconds) ok $after"
      [ "$before" = "$after" ] && exit 0
      changed=$(git -C "$repo" diff --name-only "$before" "$after")
      if echo "$changed" | grep -q '^hammerspoon/'; then
        /Applications/Hammerspoon.app/Contents/Frameworks/hs/hs -t 5 -c 'hs.reload()' >/dev/null 2>&1 || true
      fi
      if echo "$changed" | grep -q '^nixos/'; then
        # Apply the user-level half (Espanso, AeroSpace keys, Raycast scripts,
        # launchd agents, dotfiles) now, as Matt, with no password: nix-darwin
        # runs this same activate script during a full switch (2026-11-25, Matt:
        # ";scfo ... wasn't synced to my work one. solve this problem").
        # New CLI tools and system settings still wait for `rebuild`.
        flake="$repo/nixos/.config/nixos"
        hm=$(nix build --no-link --print-out-paths "$flake#darwinConfigurations.redwood-mac.config.home-manager.users.matth.home.activationPackage" 2>>"$HOME/.local/state/dotfiles-sync.err.log") || {
          notify "Config changed but didn't build; run rebuild to see why"; exit 1; }
        if ! "$hm/activate" >>"$HOME/.local/state/dotfiles-sync.log" 2>&1; then
          notify "Config changed but applying it failed; run rebuild"; exit 1
        fi
        /opt/homebrew/bin/aerospace reload-config >/dev/null 2>&1 || true
        /opt/homebrew/bin/espanso restart >/dev/null 2>&1 || true
        notify "Applied the new config. New apps or tools still need: rebuild"
      fi
    '';
  in {
    enable = true;
    config = {
      ProgramArguments = ["${script}"];
      StartInterval = 900;
      RunAtLoad = true;
      StandardOutPath = "/Users/matth/.local/state/dotfiles-sync.log";
      StandardErrorPath = "/Users/matth/.local/state/dotfiles-sync.err.log";
    };
  };
in {
  imports = [
    ./core.nix
    ./packages.nix # the full CLI/dev tool list, minus its personalOnly set (2026-11-24 red team: tig, gping, tdf, rust-analyzer... were missing)
    ./vscodium.nix # `code` alias + editor settings
    ./darwin/fact-check.nix # fetch-text; the script itself arrives via claude-config-sync
    ./darwin/raycast-scripts.nix # only its workScripts list on this machine
    ./darwin/aerospace.nix # tiling WM config (~/.aerospace.toml)
    ./darwin/aerospace-watchdog.nix # relaunch AeroSpace when it crashes or hangs
    ./darwin/karabiner.nix # caps⇄esc swap + US/Polish toggle
    ./darwin/compat-shims.nix # wl-copy/notify-send/xdg-open/... under their Linux names
    ./darwin/display-arrangement.nix # secondary display stacked above the built-in
    ./darwin/no-app-resume.nix # no "Reopen windows when logging back in"
    ./darwin/screenshot-clipboard.nix # every screenshot also lands on the clipboard
    ./darwin/borders.nix # focused-window border colours
    ./darwin/sketchybar.nix # the status bar; personal items skipped via SKETCHYBAR_WORK
    ./darwin/hammerspoon-cli.nix # the `hs` CLI
    ./darwin/memory-guard.nix # end runaway batch processes before macOS starts pausing apps
    ./darwin/claude-api-resume.nix # wake Claude Code sessions that stopped on an API error
    ./darwin/charge-limit.nix # macOS's own battery charge cap
    ./darwin/work-vault.nix # ~/Obsidian/Work: AL1-tagged notes sync with matts-mac
    ./darwin/espanso.nix # text expansion; vault/password-picker snippets skipped via my.work
    ./darwin/dayflow-guard.nix # keep Dayflow's screenshot interval at 1 s; notify when frames stop (Dayflow runs here since 11-25)
  ];

  # Extras on top of ./packages.nix (imported above, minus its personalOnly set).
  home.packages = with pkgs;
    [
      # Language servers for the Claude Code LSP plugins enabled in settings.json
      # (pyright-lsp, lua-lsp, rust-analyzer-lsp is covered by packages.nix, typescript-lsp).
      pyright
      lua-language-server
      typescript-language-server
      # Redwood devbox `rw` CLI prerequisites. Also in packages.nix's working copy
      # (uncommitted there on 2026-11-24); listing them here too keeps them on the laptop.
      awscli2
      terraform
      ssm-session-manager-plugin
      # The generic part of the personal scripts bundle (scripts/scripts.nix, which
      # also holds vault/ntfy/lifelog tools and so isn't imported here). Without
      # these, hotkeys that call them did nothing: Ctrl-Opt-C ran macOS's
      # /usr/bin/calendar, leader+digit timers, screenshot OCR, tmux Alt-N
      # (2026-11-24 red team, gap G26).
      ocrScreenshot
      (import ./scripts/scripts/kbshot/default.nix {inherit pkgs;})
      (import ./scripts/scripts/link-search/default.nix {inherit pkgs;})
      # 2026-11-27 full diff against matts-mac: tools the shipped commands call
      # that were never installed here. mpv plays "Lofi Stream" and "Brown
      # Noise" (both Raycast commands failed without it); gum is what
      # run-nix-shell-on-new-tmux-session draws its picker with.
      mpv
      gum
      # Raycast "Writing Session: Start/Stop" (words per hour); stdlib Python.
      (writeShellScriptBin "writing-session" "exec ${python3}/bin/python3 ${./scripts/scripts/writing-session.py} \"$@\"")
    ]
    ++ map (n: writeShellScriptBin n (builtins.readFile (./scripts/scripts + "/${n}.sh"))) genericScripts
    ++ [
    ];

  # Apps that open at login, as on matts-mac (./darwin/login-items.nix), minus
  # the personal ones (Beeper, Claude desktop).
  launchd.agents = lib.mkMerge [
    (lib.genAttrs ["hammerspoon" "betterdisplay" "bluesnooze"] (n: {
      enable = true;
      config = {
        ProgramArguments = [
          "/usr/bin/open"
          "-a"
          ({
              hammerspoon = "Hammerspoon";
              betterdisplay = "BetterDisplay";
              bluesnooze = "Bluesnooze";
            }.${
              n
            })
        ];
        RunAtLoad = true;
        KeepAlive = false;
        ProcessType = "Interactive";
      };
    }))
    {
      dotfiles-sync = dotfilesSync;
      claude-config-sync = claudeConfigSync;
      # Hourly "Focus check" banner, as on matts-mac (./services.nix, which also
      # holds vault jobs and so isn't imported here).
      focus-reflection-reminder = {
        enable = true;
        config = {
          ProgramArguments = [
            "${(import ./lib/platform-scripts.nix {inherit pkgs;}).notify}/bin/notify"
            "Focus check"
            "Make sure you're focused on a task and have done your reflection for it!"
          ];
          StartInterval = 3600;
          RunAtLoad = false;
        };
      };
      # Login codes from Matt's personal Gmail and Beeper texts onto the
      # clipboard, as on matts-mac (Matt, 2026-11-25: "put it on the work
      # laptop", after being told it needs his personal Gmail app password in
      # ~/notes/.env and Beeper's token in ~/.config/beeper/access-token here).
      # Both are read at runtime; neither enters the Nix store. Exits 1 while
      # APP_PASSWORD is missing, so launchd shows it failing until he adds it.
      auth-code-watcher = {
        enable = true;
        config = {
          ProgramArguments = [
            "${pkgs.writeShellScript "auth-code-watcher" ''
              exec ${pkgs.python3}/bin/python3 ${./scripts/scripts/auth-code-watcher.py} "$@"
            ''}"
          ];
          EnvironmentVariables.PATH = "${config.home.profileDirectory}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
          RunAtLoad = true;
          KeepAlive = true;
          ThrottleInterval = 30;
          StandardOutPath = "${config.home.homeDirectory}/.local/state/auth-code-watcher.log";
          StandardErrorPath = "${config.home.homeDirectory}/.local/state/auth-code-watcher.log";
        };
      };
    }
  ];

  # Raycast commands that were hand-written on matts-mac (never in Nix), copied
  # here 2026-11-25 so the laptop has them too (Matt: "copy all useful scripts").
  # Their backends are in genericScripts above; genpass ships its EFF word list.
  home.file =
    lib.listToAttrs (map (n: {
      name = ".config/raycast/scripts/${n}.sh";
      value = {
        source = ./darwin/raycast-hand + "/${n}.sh";
        executable = true;
      };
    }) ["clip2md" "grammar-check" "link-search" "screenshot-search" "tmux-sessionizer" "genpass" "focus-distracting-apps"])
    // {
      ".local/bin/genpass" = {
        source = ./darwin/raycast-hand/genpass.py;
        executable = true;
      };
      ".local/share/diceware/eff_large_wordlist.txt".source = ./darwin/raycast-hand/eff_large_wordlist.txt;
      # Marks this as the work machine (Hammerspoon's init.lua skips its personal modules).
      ".config/work-machine".text = "redwood-mac: personal Hammerspoon modules and bar items are skipped\n";
    };

  # Focus Mode's list of apps that take 15 s to reach. On matts-mac it is the
  # vault note resources/focus-mode-apps.md; here ~/notes is ~/Obsidian/Work, so
  # the same path lands in the work vault. Copied once and never overwritten:
  # Matt edits it there. It has no classification tag, so it stays on this laptop.
  home.activation.focusModeApps = lib.hm.dag.entryAfter ["writeBoundary"] ''
    f="$HOME/Obsidian/Work/resources/focus-mode-apps.md"
    if [ ! -e "$f" ]; then
      mkdir -p "$(dirname "$f")"
      cp ${./darwin/focus-mode-apps.work.md} "$f" && chmod 644 "$f"
    fi
  '';

  # Dayflow (Matt, 2026-11-25: "marshall gave the ok fro dayflow", "please
  # install dayflow on work computer"). Installed with Homebrew the first time the
  # config is applied, with matts-mac's privacy settings: no analytics, password
  # managers never captured, private windows and banking/government sites hidden,
  # one screenshot a second. Its chat and Flow focus mode stay unused: the
  # 2026-11-24 audit found chat runs Claude with permission checks off and Flow
  # ignores the app blocklist. Frames go to the Redwood Claude seat.
  home.activation.dayflow = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ ! -d /Applications/Dayflow.app ] && [ -x /opt/homebrew/bin/brew ]; then
      /opt/homebrew/bin/brew install --cask dayflow || echo "dayflow: brew install failed; run: brew install --cask dayflow" >&2
    fi
    d=teleportlabs.com.Dayflow
    /usr/bin/defaults write $d analyticsOptIn -bool false
    /usr/bin/defaults write $d browserPrivacyHidePrivateWindows -bool true
    /usr/bin/defaults write $d recordingPrivacyBlockedApplicationIdentifiers -array com.1password.1password com.bitwarden.desktop com.apple.passwords
    /usr/bin/defaults write $d browserPrivacyBlockedSiteCategories -array bankingAndFinance governmentAndTax
    /usr/bin/defaults write $d screenshotIntervalSeconds -float 1
  '';

  # Marks this as the work machine for configs Nix doesn't build: Hammerspoon's
  # init.lua skips its personal modules when this file exists.

  # Config sync (Matt, 2026-11-24): improvements made on matts-mac reach this
  # laptop without anyone copying files. ~/dotfiles is a read-only HTTPS clone
  # of the public dotfiles repo; every 15 min this pulls (fast-forward only),
  # reloads Hammerspoon when its files changed, and posts a notification when
  # the Nix config changed, since applying that needs the admin password
  # (~/redwood-kit/switch.command). One-way: nothing on this laptop is pushed.
  # Exits non-zero when a pull fails, so launchd records it.
  # Tells the shared modules to leave out personal servers, accounts and tools
  # (see ./work-flag.nix for what reads it).
  my.work = true;

  # Shell history stays on the Redwood laptop. The personal profile syncs it to
  # Matt's own Atuin account, which would carry Redwood commands off the machine.
  programs.atuin.settings.auto_sync = lib.mkForce false;

  # Commit identity: ./git.nix sets Matt's personal email. Replace it here with
  # the address Redwood wants on commits before the first switch.
  # programs.git.userEmail = lib.mkForce "CHANGE-ME@redwoodresearch.org";
}
