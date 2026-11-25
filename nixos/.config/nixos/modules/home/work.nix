# The Redwood-issued MacBook's Home Manager profile: how Matt works, with none
# of what he knows. It gets the core settings (./core.nix), the window and
# keyboard setup, and the command-line tools the shell config calls. It gets
# no vault, no lifelog, no Triage, no background jobs and no secrets.
#
# Design and reasons: the vault note
# projects/generator-residency/ai-uplift-for-ai-safety/redwood-two-laptop-design-2026-11-23.md
# App settings that live outside Nix travel in the kit (scripts/redwood-kit).
{
  pkgs,
  lib,
  ...
}: let
  dotfilesSync = let
    script = pkgs.writeShellScript "dotfiles-sync" ''
      set -u
      export PATH=${lib.makeBinPath [pkgs.git pkgs.coreutils]}:/usr/bin:/bin
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
        notify "Config changed: run ~/redwood-kit/switch.command to apply"
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
  ];

  # The subset of ./packages.nix that the shell config, Neovim and Redwood's
  # own tooling call. Personal apps (Obsidian, Beeper, Zen, gdoc-sync) stay out.
  home.packages = with pkgs; [
    eza
    fd
    fzf
    ripgrep
    jq
    duf
    procs
    unzip
    zip
    wget
    yazi
    lazygit
    pandoc
    gcc
    gnumake
    python3
    uv
    nodejs_22
    go
    awscli2
    terraform
    ssm-session-manager-plugin
    alejandra
    gitleaks
    zoxide
    pay-respects
    trash-cli
    gtrash
    btop
    tree
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
    {dotfiles-sync = dotfilesSync;}
  ];

  # Marks this as the work machine for configs Nix doesn't build: Hammerspoon's
  # init.lua skips its personal modules when this file exists.
  home.file.".config/work-machine".text = "redwood-mac: personal Hammerspoon modules and bar items are skipped\n";

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
