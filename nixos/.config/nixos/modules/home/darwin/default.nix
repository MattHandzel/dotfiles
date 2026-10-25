# The macOS-only half of the Home Manager config, imported from
# modules/home/default.nix when `pkgs.stdenv.hostPlatform.isDarwin`.
#
# The Linux counterpart is the `linuxOnly` list in that same file (Hyprland,
# waybar, swaync, fuzzel, …). Everything shared lives in the `shared` list and
# is not repeated here.
{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./aerospace.nix # tiling WM config (~/.aerospace.toml)
    ./aerospace-watchdog.nix # relaunch AeroSpace when it crashes or hangs (upstream #1311)
    ./karabiner.nix # caps⇄esc swap + US/Polish toggle
    ./compat-shims.nix # wl-copy/notify-send/xdg-open/... under their Linux names
    ./zen-config.nix # Zen prefs, macOS profile root
    ./automations.nix # calendar-agenda / disk-space-alert (system services on NixOS)
    ./memory-guard.nix # end a runaway batch job before macOS pauses apps on swap exhaustion
    ./systemstatus-guard.nix # warn to reboot before a slow systemstatusd breaks the camera in calls
    ./charge-limit.nix # battery charge cap (macOS's own Charge Limit): 100 % through 2026-10-24, then 80 %
    ./dayflow-guard.nix # keep Dayflow's screenshot interval at 1 s; notify when frames stop or slow down
    ./phone-lifelog.nix # copy the phone's location, app/screen events and Sleep Guard home log for lifelog
    ./lifelog-store.nix # every message, email and log -> ~/.local/share/lifelog store every 5 min; nightly archive + storage limits
    ./newsletter-page.nix # republish the unlisted newsletter page when its vault note or images change
    ./display-arrangement.nix # keep the secondary display stacked above the built-in (alt-k/alt-j cross monitors)
    ./login-items.nix # Beeper + Hammerspoon at login (AeroSpace does its own)
    ./bitwarden.nix # Bitwarden.app at login + Dia native-messaging bridge (Touch ID unlock in Dia)
    ./dia-extension-backup.nix # daily copy of Dia extension storage (logins) — net under dia-policy.nix
    ./no-app-resume.nix # kill "Reopen windows when logging back in", even after `sudo reboot`
    ./raycast-scripts.nix # Raycast Script Commands (timer & co.), twin of vicinae.nix
    ./wispr-clipboard-sync.nix # every Wispr Flow dictation -> clipboard -> Raycast history
    ./wispr-meeting-sync.nix # Wispr Flow meeting summaries + transcripts -> vault, calendar note, daily note
    ./wispr-learn.nix # corrections made in Neovim -> Wispr Flow dictionary (its own learner cannot see kitty)
    ./oops.nix # alt-backtick / Raycast "Oops": last 90 s of keys -> Claude -> problem log + fix
    ./claude-api-resume.nix # every Claude Code session continues by itself after an API error, sleep or lost network
    ./espanso.nix # ;; text-expansion triggers (nix-managed base.yml; Espanso.app + its own agent)
    ./sketchybar.nix # the status bar (waybar's replacement): config + launchd agent
    ./borders.nix # JankyBorders colours/width (~/.config/borders/bordersrc)
    ./kms-ingest.nix # phone captures in ~/ShareComputer/kms-inbox -> vault raw_capture (kms ingest)
    ./boox-sync.nix # BOOX cloud handwritten notes -> vault raw_capture/boox_notes (PDF + transcription), every 30 min
    ./brain-search.nix # vault semantic search, local: incremental indexer agent (query daemon starts on demand)
    ./rabbithole.nix # treadmill reader/listener web app on 127.0.0.1:8777 (tailnet :8778)
    ./downloads-to-phone.nix # new ~/Downloads files -> ~/ShareComputer/downloads -> phone
    ./screenshot-clipboard.nix # every Screenshot.app capture (⌘⇧5, Raycast "Screenshot") also -> clipboard, like the Print key
    ./morning-focus.nix # first laptop use each morning: quit messaging apps, open the daily note (CFAR TAP)
    ./message-triage.nix # Claude-triaged Beeper inbox on 127.0.0.1:8771, Ctrl-Opt-H (CFAR TAP)
    ./work-test.nix # the daily work test: Work Test.app + its server on 127.0.0.1:8772
    ./bug-listener.nix # every bug capture -> sorted on areas/bugs/bug-board.md; owned-software bugs fixed by a background Claude
    ./error-collector.nix # every error (failing agents, app logs, crashes, Hammerspoon) -> batched onto the bug board for his yes
    ./meeting-listener.nix # each finished Wispr meeting -> Haiku "real meeting?" gate -> background Opus runs the process-meeting skill
    ./shared-notes.nix # meeting notes/transcripts/docs people send Matt (Granola, Plaud, Gemini, Notion, Docs) -> stored + proposed, every 5 min
    ./person-log-sync.nix # daily: meetings/emails/DMs/calls/calendar -> areas/relationships person files (person_log.py)
    ./finance-daily.nix # daily bank sync + finance status/dashboard/audits/alerts (scripts/finance/fin daily)
    ./sleep-check.nix # each morning: did last night slip (bed after 21:30 / up after 06:45)? sent to Jeremy; agent OFF since 2026-10-22
    ./recall.nix # hourly: tag new notes with "useful when" cues, email a recall brief before each new situation on the calendar
    ./built-for-you.nix # 06:20: what Claude built for Matt -> changelog + morning email (Raycast "What's new" reads the same registry)
    ./ai-tips-radar.nix # 05:30: fetch AI-tips newsletters/feeds/skill repos; Sundays build the week's digest of tips to adopt
    ./references.nix # every 15 min: link new emails/chats/pages/meetings/captures to the projects, areas, resources they are about (refs tick)
    ./google-keep-sync.nix # every 30 min: Google Keep notes -> capture/google_keep/ (+ pointer notes like Gym Logs)
    ./retro-sweep.nix # Sun 04:15: weekly agent error sweep (retrospective-analyst over the week's transcripts -> learnings.json + Linear agent-error)
  ];

  # Home Manager's syncthing module supports darwin (it emits a launchd agent).
  # Deliberately NOT the Syncthing cask as well — two instances fighting over
  # port 8384 is a slow, quiet failure. On the NixOS laptop this is a SYSTEM
  # service (hosts/laptop/default.nix), which is why it is declared here rather
  # than in the shared list.
  services.syncthing = {
    enable = true;
    settings = {
      # The default 1% of this 926 GB disk (9.3 GB) is more than the Mac keeps
      # free while the LinuxHome mirror shares the SSD, and it stops every
      # folder. The synced data here is KBs; 1 GB is plenty of headroom.
      options.minHomeDiskFree = {
        value = 1;
        unit = "GB";
      };
      devices = {
        # Same ID the server declares (hosts/server/default.nix). The phone has
        # to accept "matts-mac" once, then accept the Recordings share.
        "Pixel 9a" = {id = "OUXTWJX-MARBGAE-ANVOBSS-ANCZDVY-QGJGWNC-YXK62MC-IPV22XX-PV3RMA5";};
        # BOOX Note Air 5C (Syncthing-Fork). It sends its note store to boox-ksync
        # below; boox-sync (boox-sync.nix) draws the notes from that copy.
        # BOOX's app freezer once disabled the app: `adb shell pm list packages -d`.
        "BOOX Note Air 5C" = {id = "F5DON6T-MEO7333-NFWDJZB-MYNKBOM-7Y3AEPQ-DNDJV24-W36U5SK-JZMRFAC";};
        # The home server: the always-on hub the phone syncs the vault through.
        # Missing until 2026-10-25, so after the laptop was sold nothing carried
        # the vault between the Mac and the server for three months. The server
        # side declares "matts-mac" in hosts/server/default.nix.
        "matts-server" = {
          id = "T3F3Y23-Z3H4TEP-GXITWXB-4WSRLZC-AO4OMQW-R6UKKG3-642JIWE-EI3PIA6";
          addresses = ["tcp://100.118.206.104:22000" "dynamic"];
        };
      };
      folders = {
        # The Obsidian vault (parent dir, holds Main/). The Mac is the source of
        # truth; the server relays it to the phone. Ignores:
        # modules/home/obsidian-vault.stignore. Doc: areas/second-brain/syncthing.md.
        "r9mpp-yvvmy" = {
          label = "Obsidian";
          path = "~/Obsidian";
          devices = ["matts-server"];
          fsWatcherEnabled = true;
          minDiskFree = {
            value = 1;
            unit = "GB";
          };
        };
        # The phone's "share computer" folder. Only kms-inbox/ (phone capture
        # JSON) is synced — see the .stignore written below; the other 5.8 GB
        # of photos/videos stay on the phone. Send-receive so the Mac-side
        # ingester's deletes of processed captures reach the phone, as the
        # NixOS laptop's did.
        "qbf3n-3ef5e" = {
          label = "ShareComputer";
          path = "~/ShareComputer";
          devices = ["Pixel 9a"];
          minDiskFree = {
            value = 1;
            unit = "GB";
          };
        };
        # The tablet's /sdcard/.ksync (its Notes app's sync store, ~11 MB), sent
        # one way: send-only on the tablet, receive-only here, so nothing on the
        # Mac can change the tablet's notes. Read by scripts/boox/boox-sync.
        # Doc: areas/second-brain/boox-sync.md.
        "boox-ksync" = {
          label = "boox-ksync";
          path = "~/.local/state/boox-sync/ksync";
          type = "receiveonly";
          devices = ["BOOX Note Air 5C"];
        };
      };
    };
  };

  # The tablet's SQLite shared-memory files change constantly and are never read.
  home.activation.booxKsyncStignore = lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
    run mkdir -p "$HOME/.local/state/boox-sync/ksync"
    run rm -f "$HOME/.local/state/boox-sync/ksync/.stignore"
    run install -m 644 ${pkgs.writeText "boox-ksync-stignore" ''
      *-shm
    ''} "$HOME/.local/state/boox-sync/ksync/.stignore"
  '';

  # A real file, not a store symlink: Syncthing won't follow a symlinked
  # .stignore. Written before launchd (re)starts syncthing.
  # This file is a WHITELIST: the trailing `*` ignores everything, and only the
  # `!`-negated paths sync. A path that is not negated here is a silent no-op --
  # files dropped at the root of ~/ShareComputer sit there forever and never
  # reach the phone (which is exactly what happened to an audiobook on
  # 2026-09-16). Negate /downloads, never `*`: the phone side of this folder
  # holds ~4.9 GB of photos and video that must stay on the phone.
  home.activation.shareComputerStignore = lib.hm.dag.entryBefore ["setupLaunchAgents"] ''
    run mkdir -p "$HOME/ShareComputer" "$HOME/ShareComputer/downloads"
    run rm -f "$HOME/ShareComputer/.stignore"
    run install -m 644 ${pkgs.writeText "sharecomputer-stignore" ''
      !/kms-inbox
      !/downloads
      *
    ''} "$HOME/ShareComputer/.stignore"
  '';

  home.sessionPath = [
    # Homebrew's Apple-silicon prefix. Casks put CLI helpers here (borders,
    # aerospace) and macOS login shells do not add it on their own.
    "/opt/homebrew/bin"
  ];

  home.packages = [
    # `pick`'s backend and the notifier are installed system-wide in
    # modules/darwin/packages.nix; these are the user-level extras the shared
    # scripts reach for.
    pkgs.pandoc
    # adb over Wireless debugging (phone Night Light, 2026-09-13 Oops)
    pkgs.android-tools
    # Mirror + control the phone in a window (Raycast "Phone", 2026-10-07)
    pkgs.scrcpy
    # DDC/CI brightness for the external monitor (DELL U3225QE): used by
    # ~/.local/bin/brightness and ~/.hammerspoon/brightness_blackout.lua
    pkgs.m1ddc
  ];

  # Hammerspoon and `brightness` call it before `rebuild` puts it on PATH.
  home.file.".local/bin/m1ddc".source = "${pkgs.m1ddc}/bin/m1ddc";
}
