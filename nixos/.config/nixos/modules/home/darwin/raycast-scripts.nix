# Raycast Script Commands — the macOS twin of the Vicinae palette commands in
# modules/home/vicinae.nix. Same backends (leader-timer & co.), Raycast's
# metadata dialect instead of Vicinae's.
#
# Raycast has ONE registered script directory, ~/.config/raycast/scripts —
# where a dozen hand-written commands already lived. 2026-09-13: it was NOT
# actually registered — every Raycast 2.x log since install said
# "[handler::script-commands] No directories configured for script discovery".
# The list lives in Raycast's encrypted settings DB (not declarable here): add
# it in Raycast Settings → Extensions → Script Commands → Add, and confirm with
#   rg 'script-commands' ~/Library/Logs/com.raycast.macos/raycast-x-*.log Everything nix-managed lands there too (2026-09-12: the first batch was
# written to a sibling script-commands/ dir Raycast never knew about, so "Oops"
# and the timers were invisible in Raycast).
#
# 2026-09-12 (evening): the migration audit found 19 of the 22 Vicinae commands
# never made it here. Every one whose backend resolves on the Mac is below;
# record-meeting and white-noise are re-implemented on launchd. Not ported:
# stt-copy/stt-type (Wispr Flow replaced them), record-area-gif (record.sh is
# wf-recorder; see the audit), session-restore (Hyprland-only). record-screen
# came back 2026-09-13 on Hammerspoon (~/.hammerspoon/screen_record.lua), which
# holds the Screen Recording grant.
#
# Added 2026-09-12 because Matt asked for the Vicinae "Timer (minutes)" command
# on the Mac: type "timer", 25, "deep work" -> notification + Glass sound when
# it fires, via the launchd-backed leader-timer (survives Raycast reaping the
# script's process group, which a plain `sleep &` would not).
{
  config,
  pkgs,
  ...
}: let
  # The same derivation scripts.nix builds (same name + content => same store
  # path). Referenced by store path, not PATH, so a home-manager-only
  # activation is enough: /etc/profiles/per-user is root-managed and only
  # catches up on Matt's next `rebuild`, which left an old leader-timer live
  # for hours on 2026-09-12.
  leaderTimer = pkgs.writeShellScriptBin "leader-timer" (builtins.readFile ../scripts/scripts/leader-timer.sh);
  timer = "${leaderTimer}/bin/leader-timer";
  keybinds = "${(import ./aerospace-helpers.nix {inherit pkgs;}).keybinds}/bin/keybinds";
  monitorMode = "${(import ./aerospace-helpers.nix {inherit pkgs;}).monitor-mode}/bin/monitor-mode";
  lofi = "${pkgs.writeShellScriptBin "lofi" (builtins.readFile ../scripts/scripts/lofi.sh)}/bin/lofi";
  lidAwake = "${pkgs.writeShellScriptBin "lid-awake" (builtins.readFile ../scripts/scripts/lid-awake.sh)}/bin/lid-awake";
  # Dayflow has no range export (Oops 20260928-130235): stitch its recording
  # chunks for a time window into one shareable mp4 in ~/Movies.
  dayflowExport = pkgs.writeShellApplication {
    name = "dayflow-export";
    runtimeInputs = [pkgs.ffmpeg pkgs.sqlite];
    text = builtins.readFile ./dayflow-export.sh;
  };
  pathPreamble = ''
    export PATH="$HOME/.local/bin:$HOME/.nix-profile/bin:/opt/homebrew/bin:/etc/profiles/per-user/matth/bin:/run/current-system/sw/bin:/usr/bin:/bin"
  '';
  script = name: body: {
    ".config/raycast/scripts/${name}.sh" = {
      executable = true;
      text = body;
    };
  };
  # Store extensions can't be installed declaratively (Raycast keeps them in
  # its encrypted DB and needs a click on Install), so `raycast-picks` walks
  # Matt through the curated list: it marks what is already installed and
  # opens each remaining store page inside Raycast. Slugs checked against
  # raycast.com on 2026-09-13 (Oops 20260913-171439); they use the manifest's
  # `owner` when it has one (linear/linear, the-browser-company/dia, …).
  raycastPicks = pkgs.writeShellScriptBin "raycast-picks" ''
    # raycast-picks            list the picks with installed/missing
    # raycast-picks install    open each missing one in Raycast, Enter = next
    # raycast-picks install 3 7  open only picks 3 and 7
    picks=(
      "linear/linear|Linear — create/search issues"
      "raycast/github|GitHub — PRs, issues, notifications"
      "marcjulian/obsidian|Obsidian — search/append vault notes"
      "jomifepe/bitwarden|Bitwarden Vault — copy passwords + TOTP"
      "limonkufu/aerospace|AeroSpace — workspaces/windows from Raycast"
      "the-browser-company/dia|Dia — search open tabs + history"
      "raycast/browser-bookmarks|Browser Bookmarks — supports Dia"
      "thomas/google-calendar|Google Calendar — upcoming events, create events"
      "jlokos/superhuman|Superhuman — search inbox, draft"
      "automattic/beeper|Beeper — chats (enable Beeper Desktop API)"
      "vitoorgomes/google-meet|Google Meet — new meeting link instantly"
      "aiotter/nixpkgs-search|NixPkgs Search — search.nixos.org in Raycast"
      "nhojb/brew|Brew — search/install/upgrade formulae + casks"
      "louishuyng/tmux-sessioner|Tmux Sessioner — create/switch tmux sessions"
      "lucaschultz/port-manager|Port Manager — who is on port N, kill it"
      "tailscale/tailscale|Tailscale — devices, copy IP/MagicDNS"
      "mooxl/coffee|Coffee — keep the Mac awake"
      "gebeto/translate|Google Translate — PL/EN translation"
      "erics118/change-case|Change Case — camel/snake/title case"
      "tonka3000/speedtest|Speedtest — internet speed test"
    )
    ext="$HOME/.config/raycast/extensions"
    installed() { grep -lqs "\"name\": *\"''${1#*/}\"" "$ext"/*/package.json; }
    mode="''${1:-list}"; shift || true
    i=0
    for p in "''${picks[@]}"; do
      i=$((i + 1)); slug="''${p%%|*}"; desc="''${p#*|}"
      if [ "$mode" = install ] && [ $# -gt 0 ] && ! printf ' %s ' "$*" | grep -q " $i "; then continue; fi
      if installed "$slug"; then state="installed"; else state="missing"; fi
      if [ "$mode" != install ]; then
        printf '%2d  %-9s  %s  (raycast.com/%s)\n' "$i" "$state" "$desc" "$slug"; continue
      fi
      [ "$state" = installed ] && [ $# -eq 0 ] && continue
      printf '%2d  %s — opening in Raycast; click Install, then Enter here (q quits) ' "$i" "$desc"
      /usr/bin/open "raycast://extensions/$slug?source=webstore"
      read -r ans; [ "$ans" = q ] && break
    done
  '';
in {
  home.packages = [dayflowExport];

  # The nix-managed scripts here are symlinks into /nix/store, and the Nix Store
  # is an encrypted volume that determinate-nixd mounts a few seconds into
  # login. Raycast (a macOS Login Item) can scan this folder before that: on
  # 2026-10-13 it scanned at 15:31:50, the store mounted at 15:31:52, and every
  # dangling link was dropped (11 scripts instead of 56, so "timer" found
  # nothing). Its watcher only rescans when a file here changes, so touch one
  # link once the store is up. /bin and /usr/bin only: this runs before /nix
  # exists.
  launchd.agents.raycast-scripts-rescan = {
    enable = true;
    config = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
    ''
          /bin/wait4path /nix/store || exit 1
          for delay in 15 60; do
            /bin/sleep "$delay"
            for f in "${config.home.homeDirectory}"/.config/raycast/scripts/*.sh; do
              [ -L "$f" ] && { /usr/bin/touch -ch "$f"; break; }
            done
          done
    ''
      ];
      RunAtLoad = true;
      KeepAlive = false;
    };
  };

  home.file =
    {".local/bin/raycast-picks".source = "${raycastPicks}/bin/raycast-picks";}
    // script "monitor-mode-toggle" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Monitor Mode: Toggle
      # @raycast.mode compact
      # @raycast.icon 🖥
      # @raycast.packageName Monitors
      # @raycast.description Switch between single (external is the only monitor; lid can close) and split (1-10 laptop, 11-20 external).
      ${monitorMode} toggle || exit
      echo "Monitor mode: $(${monitorMode} status)"
    ''
    // script "monitor-mode-single" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Monitor Mode: Single (external only)
      # @raycast.mode compact
      # @raycast.icon 🖥
      # @raycast.packageName Monitors
      # @raycast.description Every workspace moves onto the external monitor, so closing the lid changes nothing.
      ${monitorMode} single || exit
      echo "Monitor mode: single"
    ''
    // script "monitor-mode-split" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Monitor Mode: Split (1-10 laptop, 11-20 external)
      # @raycast.mode compact
      # @raycast.icon 🖥
      # @raycast.packageName Monitors
      # @raycast.description Workspaces 1-10 on the laptop screen, 11-20 on the external monitor, like the Linux setup.
      ${monitorMode} split || exit
      echo "Monitor mode: split"
    ''
    // script "timer" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Timer (minutes)
      # @raycast.mode compact
      # @raycast.icon ⏱
      # @raycast.packageName Timer
      # @raycast.argument1 { "type": "text", "placeholder": "minutes" }
      # @raycast.argument2 { "type": "text", "placeholder": "what for (optional)", "optional": true }
      # @raycast.description Start an N-minute countdown; notifies + plays a sound when done (leader-timer).
      ${pathPreamble}
      ${timer} "$1" "''${2:-}" || exit
      echo "Timer set: $1 min''${2:+ — $2}"
    ''
    // script "lid-awake" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Lid Awake
      # @raycast.mode compact
      # @raycast.icon ☕
      # @raycast.packageName Power
      # @raycast.argument1 { "type": "text", "placeholder": "seconds / 10m / off / status (blank = toggle)", "optional": true }
      # @raycast.description Keep running with the lid closed (e.g. agents at the airport). Blank toggles; 600 or 10m = awake that long, then it sleeps.
      ${lidAwake} "''${1:-toggle}" 2>&1 | tail -n 1
      exit "''${PIPESTATUS[0]}"
    ''
    // script "timer-list" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Timers: List Pending
      # @raycast.mode fullOutput
      # @raycast.icon ⏱
      # @raycast.packageName Timer
      ${pathPreamble}
      ${timer} --list
    ''
    // script "timer-cancel" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Timers: Cancel All
      # @raycast.mode compact
      # @raycast.icon ⏱
      # @raycast.packageName Timer
      ${pathPreamble}
      ${timer} --cancel
    ''
    // script "toggle-focus-mode" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Toggle Focus Mode
      # @raycast.mode silent
      # @raycast.icon 🎯
      # @raycast.packageName Focus
      ${pathPreamble}
      toggle-focus-mode || exit
      echo "Focus mode toggled"
    ''
    // script "quick-capture" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Quick Capture (text/clip/audio/screenshot)
      # @raycast.mode silent
      # @raycast.icon 📥
      # @raycast.packageName Capture
      ${pathPreamble}
      quick-capture
      echo "Capture done"
    ''
    // script "take-note" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Take Note
      # @raycast.mode compact
      # @raycast.icon 📝
      # @raycast.packageName Capture
      # @raycast.argument1 { "type": "text", "placeholder": "note text" }
      ${pathPreamble}
      take-note "$1" || exit
      echo "Noted: $1"
    ''
    // script "brain-search" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Search Second Brain
      # @raycast.mode fullOutput
      # @raycast.icon 🧠
      # @raycast.packageName Vault
      # @raycast.argument1 { "type": "text", "placeholder": "query" }
      ${pathPreamble}
      brain-search "$1"
    ''
    // script "entity-graph" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Entity Graph
      # @raycast.mode silent
      # @raycast.icon 🕸
      # @raycast.packageName Vault
      # @raycast.description Start the entity-graph server if needed and open the UI (127.0.0.1:8770).
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/entity-graph/open-entity-graph.sh"
    ''
    // script "recall" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Recall
      # @raycast.mode silent
      # @raycast.icon 🔁
      # @raycast.packageName Vault
      # @raycast.argument1 { "type": "text", "placeholder": "situation (e.g. going to EAG London)", "optional": true }
      # @raycast.description Brief me on a situation from my own past notes, messages and plans (emailed + opened in Obsidian). Empty = past briefs.
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/recall/open-recall.sh" "$1"
    ''
    // script "bug-board" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Bug Board
      # @raycast.mode silent
      # @raycast.icon 🐞
      # @raycast.packageName Vault
      # @raycast.description See and manage the bug listener's bugs: yes/no, priority, fix queue, sessions (127.0.0.1:47740).
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/bugs/open-bug-board.sh"
    ''
    // script "meeting-listener" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Meeting Listener
      # @raycast.mode fullOutput
      # @raycast.icon 🎙
      # @raycast.packageName Vault
      # @raycast.description Which finished Wispr meetings Claude is processing, queued, done or skipped (process-meeting skill).
      ${pathPreamble}
      exec python3 -I "$HOME/Obsidian/Main/scripts/meetings/meeting-listener" status
    ''
    // script "app-watch" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title App Watch
      # @raycast.mode silent
      # @raycast.icon 🔭
      # @raycast.packageName Vault
      # @raycast.description Watch how you used Work Test and Triage since the last pass (in the background; findings go on the bug board) and open the newest app-watch report.
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/app-watch/open-app-watch.sh"
    ''
    // script "phone" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Phone
      # @raycast.mode compact
      # @raycast.icon 📱
      # @raycast.packageName Vault
      # @raycast.description Connect adb to the Pixel over Tailscale and mirror its screen with scrcpy.
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/phone/open-phone.sh"
    ''
    // script "predictions" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Predictions
      # @raycast.mode silent
      # @raycast.icon 🎯
      # @raycast.packageName Vault
      # @raycast.description Open the predictions UI (127.0.0.1:7337), restarting its launchd agent if needed.
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/raycast/open-launchd-ui.sh" http://127.0.0.1:7337/ org.nix-community.home.predict-ui
    ''
    // script "rabbithole" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Rabbithole
      # @raycast.mode silent
      # @raycast.icon 🐇
      # @raycast.packageName Vault
      # @raycast.description Open Rabbithole (127.0.0.1:8777), restarting its launchd agent if needed.
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/raycast/open-launchd-ui.sh" http://127.0.0.1:8777/ org.nix-community.home.rabbithole
    ''
    // script "finance-dashboard" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Finance Dashboard
      # @raycast.mode silent
      # @raycast.icon 💵
      # @raycast.packageName Vault
      # @raycast.description Open the local finance dashboard (fin open).
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/finance/fin" open
    ''
    // script "finance-status" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Finance Status
      # @raycast.mode fullOutput
      # @raycast.icon 💵
      # @raycast.packageName Vault
      # @raycast.description Net worth, runway and findings (fin status).
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/finance/fin" status
    ''
    // script "captures-db" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Captures DB
      # @raycast.mode silent
      # @raycast.icon 🗃
      # @raycast.packageName Vault
      # @raycast.description Start the captures DB UI if needed (127.0.0.1:47631) and open it.
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/captures-db/open-captures-db.sh"
    ''
    // script "lifelog" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Lifelog
      # @raycast.mode silent
      # @raycast.icon 🗂
      # @raycast.packageName Lifelog
      # @raycast.description Start the lifelog web UI if needed (127.0.0.1:47318) and open it: day timeline with screenshots, search, people, week plan vs actual, trends, data.
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/lifelog/open-lifelog.sh"
    ''
    // script "ai-catalog" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title AI Catalog
      # @raycast.mode silent
      # @raycast.icon 🧭
      # @raycast.packageName Vault
      # @raycast.description Everything I use AI for: usage, dated examples, demos, and drafted answers (127.0.0.1:47452).
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/ai-catalog/open-ai-catalog.sh"
    ''
    // script "writing-session" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Writing Session: Start/Stop (words/hour)
      # @raycast.mode compact
      # @raycast.icon ✍️
      # @raycast.packageName Writing
      ${pathPreamble}
      writing-session toggle || exit
    ''
    // script "writing-report" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Writing Sessions: Recent Speed
      # @raycast.mode fullOutput
      # @raycast.icon ✍️
      # @raycast.packageName Writing
      ${pathPreamble}
      writing-session report
    ''
    // script "password-type" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Password: Type Into Focused Window
      # @raycast.mode silent
      # @raycast.icon 🔑
      # @raycast.packageName Passwords
      ${pathPreamble}
      password-picker || exit
      echo "Password picker done"
    ''
    // script "password-copy" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Password: Copy (auto-clears 45s)
      # @raycast.mode silent
      # @raycast.icon 🔑
      # @raycast.packageName Passwords
      ${pathPreamble}
      password-picker copy || exit
      echo "Password copied"
    ''
    // script "ocr-screenshot" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title OCR Screenshot → Clipboard
      # @raycast.mode silent
      # @raycast.icon 🔍
      # @raycast.packageName Screenshots
      ${pathPreamble}
      ocr-screenshot
      echo "OCR result in clipboard"
    ''
    # `read-aloud` on this PATH is ~/.local/bin's ~/Projects/readaloud prototype,
    # not the nix one: bare = read selection → tab → clipboard in the floating
    # reader window (which has the transport buttons); --toggle only pauses a
    # running session; there is no --menu/--seek. The Linux-style "toggle" +
    # "Control Panel" pair never started a read (Oops 20261006-171347).
    // script "read-aloud" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Read Aloud
      # @raycast.mode silent
      # @raycast.icon 🔊
      # @raycast.packageName Read Aloud
      ${pathPreamble}
      read-aloud
    ''
    // script "read-aloud-pause" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Read Aloud: Pause / Resume
      # @raycast.mode silent
      # @raycast.icon ⏯️
      # @raycast.packageName Read Aloud
      ${pathPreamble}
      read-aloud --toggle || { echo "Nothing is being read"; exit 1; }
      echo "Paused / resumed"
    ''
    // script "read-aloud-stop" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Read Aloud: Stop
      # @raycast.mode silent
      # @raycast.icon ⏹️
      # @raycast.packageName Read Aloud
      ${pathPreamble}
      read-aloud --stop
      echo "Stopped reading"
    ''
    // script "send-to-phone" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Send Text to Phone (ntfy)
      # @raycast.mode compact
      # @raycast.icon 📱
      # @raycast.packageName Phone
      # @raycast.argument1 { "type": "text", "placeholder": "message" }
      ${pathPreamble}
      send-to-phone-ntfy "$1" || exit
      echo "Sent to phone"
    ''
    // script "wallpaper" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Change Wallpaper
      # @raycast.mode silent
      # @raycast.icon 🖼
      # @raycast.packageName Desktop
      ${pathPreamble}
      wallpaper-picker
      echo "Wallpaper picker done"
    ''
    // script "keybinds" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Show Keybinds Cheatsheet
      # @raycast.mode silent
      # @raycast.icon ⌨️
      # @raycast.packageName Desktop
      ${pathPreamble}
      ${keybinds}
      echo "Keybinds shown"
    ''
    // script "lofi" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Lofi Stream (toggle)
      # @raycast.mode compact
      # @raycast.icon 🎵
      # @raycast.packageName Audio
      ${pathPreamble}
      ${lofi} && echo "lofi toggled"
    ''
    // script "white-noise" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Brown Noise (toggle)
      # @raycast.mode compact
      # @raycast.icon 🌊
      # @raycast.packageName Audio
      # @raycast.description mpv generates brown noise on the fly (no file, no network); run again to stop.
      ${pathPreamble}
      label="com.matth.white-noise"
      if launchctl list "$label" >/dev/null 2>&1; then
        launchctl remove "$label"; echo "Brown noise off"; exit 0
      fi
      launchctl submit -l "$label" -- ${pkgs.mpv}/bin/mpv --no-video --no-terminal --volume=60 av://lavfi:anoisesrc=color=brown:amplitude=0.5 || exit
      echo "Brown noise on"
    ''
    // script "record-screen" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Record Screen (toggle)
      # @raycast.mode silent
      # @raycast.icon 🔴
      # @raycast.packageName Capture
      # @raycast.description Screen recording to ~/Videos/<time>.mov (Hammerspoon screencapture -v); run again to stop, the path lands on the clipboard. For an area/window use ⌘⇧5.
      /usr/bin/open -g "hammerspoon://screen-record"
      echo "Screen recording toggled"
    ''
    // script "record-meeting" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Record Meeting (toggle)
      # @raycast.mode compact
      # @raycast.icon 🎙
      # @raycast.packageName Capture
      # @raycast.argument1 { "type": "text", "placeholder": "meeting name", "optional": true }
      # @raycast.description Audio-only from the default mic (AVFoundation device :0) into ~/notes/capture/meetings; run again to stop.
      ${pathPreamble}
      label="com.matth.meeting-rec"; DIR="$HOME/notes/capture/meetings"; NAMEFILE="$HOME/.local/state/meeting-rec.name"
      if launchctl list "$label" >/dev/null 2>&1; then
        launchctl remove "$label"
        echo "Stopped: $(cat "$NAMEFILE" 2>/dev/null)"; rm -f "$NAMEFILE"; exit 0
      fi
      mkdir -p "$DIR" "$(dirname "$NAMEFILE")"
      safe=$(printf '%s' "''${1:-meeting}" | tr -c '[:alnum:]._-' '_')
      out="$DIR/$(date +%Y-%m-%d_%H-%M-%S)_$safe.wav"
      launchctl submit -l "$label" -- ${pkgs.ffmpeg}/bin/ffmpeg -hide_banner -loglevel error -f avfoundation -i ":0" -ac 1 -ar 16000 "$out" || exit
      echo "$out" > "$NAMEFILE"; echo "Recording → $out"
    ''
    // script "dayflow-export" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Dayflow: Export Video
      # @raycast.mode compact
      # @raycast.icon 🎞
      # @raycast.packageName Dayflow
      # @raycast.argument1 { "type": "text", "placeholder": "from (9:25)" }
      # @raycast.argument2 { "type": "text", "placeholder": "to (12:55)" }
      # @raycast.argument3 { "type": "text", "placeholder": "date (today)", "optional": true }
      # @raycast.description Stitch today's Dayflow screen recording between two times into one mp4 in ~/Movies (10 fps timelapse) and reveal it in Finder.
      ${pathPreamble}
      ${dayflowExport}/bin/dayflow-export "$1" "$2" ''${3:+"$3"} | tail -1
    ''
    // script "lifelog-search" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Lifelog: Search
      # @raycast.mode fullOutput
      # @raycast.icon 🔎
      # @raycast.packageName Lifelog
      # @raycast.argument1 { "type": "text", "placeholder": "words (messages, email, screen notes, pages, commands...)" }
      # @raycast.argument2 { "type": "text", "placeholder": "days (default 180; all)", "optional": true }
      # @raycast.description Full-text search over the lifelog store: every Beeper message, every email, Dayflow, windows, pages, commands, dictations, prompts, captures.
      ${pathPreamble}
      case "''${2:-}" in
        "") exec python3 -I "$HOME/Obsidian/Main/scripts/lifelog/lifelog.py" find "$1" --max 80 ;;
        all) exec python3 -I "$HOME/Obsidian/Main/scripts/lifelog/lifelog.py" find "$1" --all --max 80 ;;
        *) exec python3 -I "$HOME/Obsidian/Main/scripts/lifelog/lifelog.py" find "$1" --days "$2" --max 80 ;;
      esac
    ''
    // script "lifelog-check" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Lifelog: Did I Already Do This?
      # @raycast.mode fullOutput
      # @raycast.icon ✅
      # @raycast.packageName Lifelog
      # @raycast.argument1 { "type": "text", "placeholder": "action item (send Lincoln the recording)" }
      # @raycast.argument2 { "type": "text", "placeholder": "who (comma-separated; default: names in it)", "optional": true }
      # @raycast.argument3 { "type": "text", "placeholder": "since (2026-10-18 11:00, 3d; default 14d)", "optional": true }
      # @raycast.description The lifelog done-check: searches every source (sent mail and messages, Wispr shares, invites, Drive shares, Dayflow, exports) for the item and gives done / partly / not done / can't see, with the evidence and what it can't see.
      ${pathPreamble}
      exec python3 -I "$HOME/Obsidian/Main/scripts/lifelog/lifelog.py" check "$1" ''${2:+--who "$2"} ''${3:+--after "$3"}
    ''
    // script "lifelog-messages" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Lifelog: Messages With
      # @raycast.mode fullOutput
      # @raycast.icon 💬
      # @raycast.packageName Lifelog
      # @raycast.argument1 { "type": "text", "placeholder": "person or chat" }
      # @raycast.argument2 { "type": "text", "placeholder": "containing (optional)", "optional": true }
      # @raycast.description Every message with a person or chat, on any Beeper network, from the lifelog store (last year).
      ${pathPreamble}
      exec python3 -I "$HOME/Obsidian/Main/scripts/lifelog/lifelog.py" messages "$1" ''${2:+--text "$2"} --max 150
    ''
    // script "lifelog-storage" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Lifelog: Storage
      # @raycast.mode fullOutput
      # @raycast.icon 💾
      # @raycast.packageName Lifelog
      # @raycast.description What every log weighs, how fast it grows, the limits in policy.toml, and the store's sources.
      ${pathPreamble}
      python3 -I "$HOME/Obsidian/Main/scripts/lifelog/lifelog.py" storage
      echo
      python3 -I "$HOME/Obsidian/Main/scripts/lifelog/lifelog.py" stats
    ''
    // script "publish-newsletter-page" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Publish Newsletter Page
      # @raycast.mode fullOutput
      # @raycast.icon 💌
      # @raycast.packageName Vault
      # @raycast.description Rebuild the unlisted newsletter page from the vault note and deploy it (it also runs by itself when the note or its images change).
      ${pathPreamble}
      exec "$HOME/Obsidian/Main/scripts/newsletter/publish-private-page.sh"
    ''
    # Oops 20261015-175208: Matt typed "vault sync" in Raycast to push a note he
    # had just edited to matthandzel.com, and nothing matched — the sync only ran
    # hourly. The title holds both "vault … sync" and "website sync" in order so
    # either query finds it. It kickstarts the launchd job (services.nix) instead
    # of running the sync itself: launchd never starts a second copy, the run
    # gets the hourly job's env and log rotation, and closing Raycast cannot kill
    # a sync halfway.
    // script "website-sync" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Vault → Website Sync
      # @raycast.mode fullOutput
      # @raycast.icon 🌐
      # @raycast.packageName Vault
      # @raycast.description Push the vault to matthandzel.com now (the hourly personal-website-sync job), follow it, and list the notes it published.
      ${pathPreamble}
      label="gui/$(id -u)/org.nix-community.home.personal-website-sync"
      log="$HOME/Projects/website/sync.log"
      state() { launchctl print "$label" 2>/dev/null | awk '$1 == "state" {print $3; exit}'; }
      # the log lines after the newest "Starting Website Sync at" marker, from its last $1 lines
      this_run() { tail -n "$1" "$log" | awk '/^Starting Website Sync at /{n=0} {l[n++]=$0} END{for (i=0; i<n; i++) print l[i]}'; }
      written_since_start() { [ "$(/usr/bin/stat -f %m "$log")" -ge "$start" ]; }
      if [ "$(state)" = running ]; then
        echo "A website sync is already running; following it."
      else
        launchctl kickstart "$label" || { echo "launchctl kickstart $label failed"; exit 1; }
        echo "Started the website sync at $(date +%H:%M:%S)."
      fi
      start=$(date +%s)
      for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(state)" = running ] && break; sleep 0.5; done
      last=""
      while [ "$(state)" = running ]; do
        el=$(( $(date +%s) - start ))
        if [ "$el" -ge 3600 ]; then echo "Still running after an hour; it carries on in launchd. Log: $log"; exit 0; fi
        # until the run writes, the log's tail is the previous run's
        phase=""
        written_since_start && phase=$(this_run 400 | grep -E '^(these [0-9]+ paths will be fetched|copying path|Starting [A-Za-z]+\.\.\.$|Processing complete!)' | tail -1)
        case "$phase" in these* | copying*) phase="fetching the nix-shell dependencies" ;; esac
        if [ -n "$phase" ] && [ "$phase" != "$last" ]; then printf '%5ss  %s\n' "$el" "$phase"; last=$phase; fi
        sleep 3
      done
      if ! written_since_start; then
        echo "The job ended without writing to $log. Check: launchctl print $label"
        exit 1
      fi
      run=$(this_run 40000)
      code=$(launchctl print "$label" | awk -F' = ' '/last exit code|last terminating signal/ {print $2; exit}')
      echo
      echo "$run" | grep -E '^(Starting Website Sync|Sync completed|Skipped) at'
      echo "exit: $code    errors logged: $(echo "$run" | grep -c ' - ERROR - ')"
      published=$(echo "$run" | grep -E '^Buffered (note:|(content|blog post) \(public\))' | sort -u)
      echo
      if [ -n "$published" ]; then
        echo "Published (notes live at matthandzel.com/notes/<id>):"
        echo "$published" | sed 's/^/  /'
      elif echo "$run" | grep -q '^Skipped at '; then
        echo "Nothing was synced: the Mac is offline. Run this again once it's back online."
      else
        echo "Nothing new to publish since the last run."
      fi
      [ "$code" = 0 ] || { echo; echo "The sync failed; last lines of $log:"; echo "$run" | tail -n 15; exit 1; }
    ''
    # Built for you (2026-10-19, Matt: "the surfaces should be "raycast: what's new" and an email"): what Claude
    # built for him lately, from areas/built-for-you/registry.json. Doc: areas/second-brain/built-for-you.md
    // script "whats-new" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title What's New
      # @raycast.mode fullOutput
      # @raycast.icon 🎁
      # @raycast.packageName Vault
      # @raycast.argument1 { "type": "text", "placeholder": "5 keep, drop 8 9, keep all, ok", "optional": true }
      # @raycast.description What Claude built for you lately. With no argument it opens the decision page (one button per item). Type a number and a word to act on one.
      ${pathPreamble}
      if [ -n "''${1:-}" ]; then
        exec python3 -I "$HOME/Obsidian/Main/scripts/built-for-you/bfy" whatsnew --action "$1"
      fi
      "$HOME/Obsidian/Main/scripts/built-for-you/open-decide.sh" >/dev/null 2>&1 || true
      exec python3 -I "$HOME/Obsidian/Main/scripts/built-for-you/bfy" whatsnew
    ''
    // script "stage-meeting-drafts" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Stage Meeting Drafts
      # @raycast.mode fullOutput
      # @raycast.icon 📨
      # @raycast.packageName Vault
      # @raycast.description Swapcard follow-ups one at a time (clipboard + chat), plus any Beeper draft the 10-min auto run left pending. Never sends.
      ${pathPreamble}
      exec python3 -I "$HOME/Obsidian/Main/scripts/meetings/stage-drafts"
    ''
    // script "letter-send" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Letter Send
      # @raycast.mode compact
      # @raycast.icon ✉️
      # @raycast.packageName Newsletter
      # @raycast.description Dry-run the newest written newsletter issue, then open the click-to-send page (just opens it if already running).
      ${pathPreamble}
      exec "$HOME/Projects/personal-newsletter/scripts/letter-send.sh"
    ''
    // script "ai-tips" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title AI Tips
      # @raycast.mode fullOutput
      # @raycast.icon 💡
      # @raycast.packageName Vault
      # @raycast.argument1 { "type": "text", "placeholder": "3 adopt, 3 skip, 3 show, add <url>", "optional": true }
      # @raycast.description This week's tips from your AI newsletters, feeds and skill repos, checked against your setup. "3 adopt" has a Claude session build one in; "add <url>" follows a new newsletter or repo.
      ${pathPreamble}
      R="$HOME/Obsidian/Main/scripts/ai-tips-radar/radar"
      case "''${1:-}" in
        "") exec python3 -I "$R" list ;;
        add\ *) exec python3 -I "$R" add-source "''${1#add }" ;;
        *) exec python3 -I "$R" list --action "$1" ;;
      esac
    ''
    // script "sleep-check" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Sleep Check
      # @raycast.mode fullOutput
      # @raycast.icon 🌙
      # @raycast.packageName Vault
      # @raycast.description Did last night slip (bed after 21:30 / up after 06:45)? Mode, streak, data freshness, and the last 14 nights.
      ${pathPreamble}
      python3 -I "$HOME/Obsidian/Main/scripts/sleep-check/sleep_check.py" status
      echo
      python3 -I "$HOME/Obsidian/Main/scripts/sleep-check/sleep_check.py" backtest --days 14
    ''
    // script "person-sync" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Person Sync
      # @raycast.mode fullOutput
      # @raycast.icon 👥
      # @raycast.packageName People
      # @raycast.description Sync every meeting, email, DM chat, call and calendar event into the people's files now (LLM settles ambiguous names).
      ${pathPreamble}
      bash "$HOME/Obsidian/Main/scripts/relationships/person-log-sync.sh" --llm 2>&1 | tail -n 15
    ''
    // script "who-is-this" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Who Is This
      # @raycast.mode silent
      # @raycast.icon 👥
      # @raycast.packageName People
      # @raycast.description Open the people the resolver couldn't pin down (answer with Confirm Person).
      bash "$HOME/Obsidian/Main/scripts/relationships/who-is-this.sh"
    ''
    // script "confirm-person" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Confirm Person
      # @raycast.mode compact
      # @raycast.icon 👥
      # @raycast.packageName People
      # @raycast.argument1 { "type": "text", "placeholder": "mention (as written)" }
      # @raycast.argument2 { "type": "text", "placeholder": "slug or none" }
      # @raycast.argument3 { "type": "text", "placeholder": "scope, e.g. chat:… (optional)", "optional": true }
      # @raycast.description Tell the resolver who a name/handle is; remembered for good.
      ${pathPreamble}
      bash "$HOME/Obsidian/Main/scripts/relationships/confirm-person.sh" "$1" "$2" "''${3:-}" 2>&1 | tail -n 1
    ''
    // script "resolve-person" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Resolve Person
      # @raycast.mode fullOutput
      # @raycast.icon 👥
      # @raycast.packageName People
      # @raycast.argument1 { "type": "text", "placeholder": "name, handle or email" }
      # @raycast.argument2 { "type": "text", "placeholder": "date YYYY-MM-DD (optional)", "optional": true }
      # @raycast.description Who is this? Best match, evidence, and their profile path.
      ${pathPreamble}
      bash "$HOME/Obsidian/Main/scripts/relationships/resolve-person.sh" "$1" "''${2:-}"
    '';
}
