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
{pkgs, ...}: let
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
  pathPreamble = ''
    export PATH="/opt/homebrew/bin:/etc/profiles/per-user/matth/bin:/run/current-system/sw/bin:$HOME/.local/bin:/usr/bin:/bin"
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
    // script "lifelog-search" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Lifelog Search
      # @raycast.mode silent
      # @raycast.icon 🗂
      # @raycast.packageName Vault
      ${pathPreamble}
      lifelog-search || exit
      echo "Lifelog opened"
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
    // script "read-aloud" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Read Selection Aloud (toggle)
      # @raycast.mode silent
      # @raycast.icon 🔊
      # @raycast.packageName Read Aloud
      ${pathPreamble}
      read-aloud --toggle
      echo "Read-aloud toggled"
    ''
    // script "read-aloud-menu" ''
      #!/usr/bin/env bash
      # @raycast.schemaVersion 1
      # @raycast.title Read Aloud: Control Panel
      # @raycast.mode silent
      # @raycast.icon 🔊
      # @raycast.packageName Read Aloud
      ${pathPreamble}
      read-aloud --menu
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
    '';
}
