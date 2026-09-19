# The two launch helpers behind the AeroSpace app hotkeys (aerospace.nix):
#
#   focus-app     — the macOS port of the laptop's focus_app: jump to the app's
#                   own workspace and focus its window, or launch it there.
#   dwindle-open  — Hyprland-dwindle feel: after the launched window appears,
#                   join it with the window you launched from along that
#                   window's LONGER side (join-with; split is a no-op here).
#
# Both are copies of the ~/.local/bin versions Matt tuned live on 2026-09-10,
# adjusted only for writeShellApplication's `set -euo pipefail` (a missing
# window or a stopped AeroSpace server must not abort the launch).
#
# `aerospace` is deliberately the CLI that ships with the cask
# (/opt/homebrew/bin), not pkgs.aerospace: the client refuses to talk to a
# server of a different version, and the server is the cask's.
{pkgs}: let
  homebrewBin = "/opt/homebrew/bin";
  # `open` and `osascript` live in /usr/bin; AeroSpace's [exec] env-vars supply
  # that, but the scripts are also run from shells and launchd agents that may not.
  systemBin = "/usr/bin:/bin";
in rec {
  dwindle-open = pkgs.writeShellApplication {
    name = "dwindle-open";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      # Usage: dwindle-open <command...>
      #
      # REWRITTEN 2026-09-12. The old version ran `aerospace split` before the
      # launch. The AeroSpace docs say split "has no effect if
      # enable-normalization-flatten-containers is turned on" — which it is —
      # so every hotkey paid a 0.7 s System Events round-trip for nothing and
      # windows still just piled up as ever-narrower columns.
      #
      # Now: launch IMMEDIATELY (the hotkey must feel instant), then wait up
      # to 8 s for the new window to show up, then use
      # `join-with`, the command the docs recommend instead of split. join-with
      # nests the new window with its neighbour in a container of the OPPOSITE
      # orientation, which is exactly a Hyprland dwindle step:
      #   parent is a row    and the window you launched from was TALLER than wide
      #     -> stack the new window under it   (join-with left)
      #   parent is a column and the launching window was WIDER than tall
      #     -> put the new window beside it     (join-with up)
      #   otherwise the plain append already splits the long side; do nothing.
      # Shape comes from one System Events size query addressed by pid+title,
      # so it is immune to focus moving while the app starts. Orientation comes
      # from AeroSpace's own %{window-parent-container-layout} — no guessing.
      export PATH="${homebrewBin}:$PATH:${systemBin}"
      prev=$(aerospace list-windows --focused --format '%{window-id}|%{app-pid}|%{window-title}|%{workspace}' 2>/dev/null || true)
      # Launch FIRST, in the background, so the hotkey is instant; then watch in
      # the FOREGROUND. A detached `( … ) &` watcher was reaped with the
      # launcher's process group (by AeroSpace's exec-and-forget and by any
      # shell), so it never lived long enough to see the window (2026-09-12).
      "$@" >/dev/null 2>&1 &
      if [ -n "$prev" ]; then
          IFS='|' read -r pid ppid ptitle pws <<<"$prev"
          w=""; h=""
          # By PID, not by app name: `open -na kitty` starts one kitty PROCESS per
          # window, and `process "kitty"` in System Events is whichever came first.
          read -r w h < <(osascript -e 'on run argv' -e 'tell application "System Events" to tell (first process whose unix id is ((item 1 of argv) as integer)) to get size of window (item 2 of argv)' -e 'end run' "$ppid" "$ptitle" 2>/dev/null | tr -d ",") || true
          [ -n "$w" ] && [ -n "$h" ] || exit 0
          i=0
          while [ $i -lt 40 ]; do   # 40 x 0.2 s = 8 s for slow launches (Anki, Zoom)
            cur=$(aerospace list-windows --focused --format '%{window-id}|%{workspace}|%{window-parent-container-layout}' 2>/dev/null || true)
            IFS='|' read -r cid cws playout <<<"$cur"
            if [ -n "$cid" ] && [ "$cid" != "$pid" ] && [ "$cws" = "$pws" ]; then
              case "$playout" in
                h_tiles) if [ "$h" -gt "$w" ]; then aerospace join-with left >/dev/null 2>&1 || true; fi ;;
                v_tiles) if [ "$w" -ge "$h" ]; then aerospace join-with up >/dev/null 2>&1 || true; fi ;;
              esac
              exit 0
            fi
            sleep 0.2; i=$((i + 1))
          done
      fi
      exit 0
    '';
  };

  # aerospace-retile — drag every EXISTING window back into the tiling layer.
  #
  # WHY THIS HAS TO EXIST: `on-window-detected` only fires when AeroSpace SEES a
  # window appear. Windows that were already open when AeroSpace started never
  # get that callback, so the catch-all `run = 'layout tiling'` never touches
  # them and they sit outside the layout looking like tiling is broken. That is
  # the normal state after every AeroSpace restart, which start-at-login now
  # makes a daily event rather than a rare one.
  aerospace-retile = pkgs.writeShellApplication {
    name = "aerospace-retile";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      export PATH="${homebrewBin}:$PATH:${systemBin}"
      for ws in $(aerospace list-workspaces --all 2>/dev/null); do
        ids=$(aerospace list-windows --workspace "$ws" --format '%{window-id}' 2>/dev/null || true)
        [ -z "$ids" ] && continue
        for id in $ids; do
          # already-tiling windows make this a noop and a non-zero exit; ignore.
          aerospace layout tiling --window-id "$id" >/dev/null 2>&1 || true
        done
        aerospace flatten-workspace-tree --workspace "$ws" >/dev/null 2>&1 || true
        # A workspace whose ROOT is an accordion shows every window stacked on
        # top of each other (30 px offset) — indistinguishable from "tiling is
        # broken". Nothing in this config binds accordion on purpose, yet
        # workspace 1 was found in h_accordion on 2026-09-12. Normalise to tiles.
        root=$(aerospace list-windows --workspace "$ws" --format '%{workspace-root-container-layout}' 2>/dev/null | head -1 || true)
        case "$root" in
          *accordion*) first=$(echo "$ids" | head -1); aerospace layout h_tiles --window-id "$first" >/dev/null 2>&1 || true ;;
        esac
      done
    '';
  };

  # float-open — launch a command and float the window IT opens (alt-shift-t).
  #
  # The binding used to be ['layout floating', 'exec-and-forget open -na kitty'],
  # which floats the window that is focused WHEN THE KEY IS PRESSED (Dia, say)
  # and then lets the catch-all tile the new kitty. Floating a tile is the
  # "tiling window manager is not tiling" report (Oops 20260913-154056).
  float-open = pkgs.writeShellApplication {
    name = "float-open";
    runtimeInputs = [pkgs.coreutils float-log];
    text = ''
      export PATH="${homebrewBin}:$PATH:${systemBin}"
      # Only a window that did not exist before the launch is floated. Checking
      # "focus moved" alone would float Dia if alt-1 is pressed before kitty
      # appears (Oops 20260913-155858).
      before=" $(aerospace list-windows --monitor all --format '%{window-id}' 2>/dev/null | tr '\n' ' ' || true)"
      "$@" >/dev/null 2>&1 &
      i=0
      while [ $i -lt 40 ]; do   # 8 s
        cur=$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null || true)
        if [ -n "$cur" ] && [[ "$before" != *" $cur "* ]]; then
          aerospace layout floating --window-id "$cur" >/dev/null 2>&1 || true
          float-log "$cur" floating float-open
          exit 0
        fi
        sleep 0.2; i=$((i + 1))
      done
    '';
  };

  # float-log <window-id> <layout> <source> — one line per float/tile change
  # made from a hotkey, in ~/.local/state/aerospace-float.log. AeroSpace keeps no
  # history, so a window found floating had no visible cause (Oops
  # 20260913-154056, -155858). ~/.hammerspoon/tile_guard.lua reads this file to
  # leave windows Matt floated on purpose alone, and logs its own re-tiles here.
  float-log = pkgs.writeShellApplication {
    name = "float-log";
    runtimeInputs = [pkgs.coreutils pkgs.gawk];
    text = ''
      export PATH="${homebrewBin}:$PATH:${systemBin}"
      info=$(aerospace list-windows --monitor all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null \
        | awk -F'|' -v id="$1" '$1==id {print $2" | "$3; exit}' || true)
      mkdir -p "$HOME/.local/state"
      printf '%s %s %s %s %s %s\n' "$(date +%s)" "$(date '+%F %T')" "$1" "$2" "$3" "$info" >> "$HOME/.local/state/aerospace-float.log"
    '';
  };

  # float-toggle — alt-space. Same as `layout floating tiling`, plus a float-log line.
  float-toggle = pkgs.writeShellApplication {
    name = "float-toggle";
    runtimeInputs = [pkgs.coreutils float-log];
    text = ''
      export PATH="${homebrewBin}:$PATH:${systemBin}"
      focused=$(aerospace list-windows --focused --format '%{window-id}|%{app-pid}' 2>/dev/null || true)
      id=''${focused%%|*}
      [ -n "$id" ] || exit 0
      # Only toggle a window Matt can see. With an unmanaged panel frontmost
      # (Raycast, Spotlight) AeroSpace's focused window is the one hidden behind
      # it: ⌥␣ over Raycast on ws notetaker floated kitty "notetaker" unseen
      # (Oops 20260913-163425, pressed 15:44:19 in 20260913-154432/keys.log).
      front=$(lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null | tr -dc '0-9' || true)
      if [ -n "$front" ] && [ "$front" != "''${focused#*|}" ]; then
        float-log "$id" skipped "alt-space-front-pid-$front"
        exit 0
      fi
      aerospace layout floating tiling --window-id "$id" >/dev/null 2>&1 || true
      layout=$(aerospace list-windows --focused --format '%{window-layout}' 2>/dev/null || true)
      case "$layout" in floating) l=floating ;; *) l=tiling ;; esac
      float-log "$id" "$l" alt-space
    '';
  };

  # monitor-mode — how workspaces are spread over the laptop + an external monitor
  # (2026-09-14). State lives in ~/.local/state/monitor-mode; Raycast "Monitor
  # Mode" toggles it and ~/.hammerspoon/monitor_mode.lua re-applies it whenever a
  # screen is plugged in, unplugged, or the lid opens/closes.
  #
  #   single — the external monitor is THE monitor: workspaces 1-20 and every app
  #            workspace move onto it, so closing the lid changes nothing.
  #   split  — the Linux layout (hyprland/displays.nix): 1-10 on the laptop,
  #            11-20 on the external. App workspaces stay where they are; they
  #            follow the focused monitor instead (focus-app, on-window-detected).
  #
  # With one screen there is nothing to arrange; the mode is still recorded.
  monitor-mode = pkgs.writeShellApplication {
    name = "monitor-mode";
    runtimeInputs = [pkgs.coreutils pkgs.gawk];
    text = ''
      # monitor-mode [toggle|single|split|apply|status]
      export PATH="${homebrewBin}:$PATH:${systemBin}"
      state="$HOME/.local/state/monitor-mode"
      mkdir -p "$(dirname "$state")"
      mode=$(cat "$state" 2>/dev/null || echo split)
      case "$mode" in single|split) ;; *) mode="split" ;; esac
      cmd="''${1:-apply}"
      case "$cmd" in
        status) echo "$mode"; exit 0 ;;
        toggle) if [ "$mode" = single ]; then mode="split"; else mode="single"; fi ;;
        single|split) mode="$cmd" ;;
        apply) ;;
        *) echo "usage: monitor-mode [toggle|single|split|apply|status]" >&2; exit 2 ;;
      esac
      echo "$mode" > "$state"

      notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Monitor mode\"" >/dev/null 2>&1 || true; }
      label() { if [ "$mode" = single ]; then echo "single: everything on the external monitor"; else echo "split: 1-10 laptop, 11-20 external"; fi; }

      mons=$(aerospace list-monitors --format '%{monitor-id}|%{monitor-name}' 2>/dev/null || true)
      builtin=$(echo "$mons" | awk -F'|' '$2 ~ /Built-in/ {print $1; exit}')
      external=$(echo "$mons" | awk -F'|' '$2 !~ /Built-in/ {print $1; exit}')
      if [ -z "$builtin" ] || [ -z "$external" ]; then
        [ "$cmd" = apply ] || notify "$(label) (one screen: applies when both are connected)"
        exit 0
      fi

      focused=$(aerospace list-workspaces --focused 2>/dev/null || true)
      where=$(aerospace list-workspaces --all --format '%{workspace}|%{monitor-id}' 2>/dev/null || true)
      move() {  # move <workspace> <monitor-id>, skipped when it is already there
        cur=$(echo "$where" | awk -F'|' -v w="$1" '$1==w {print $2; exit}')
        [ "$cur" = "$2" ] && return 0
        aerospace move-workspace-to-monitor --workspace "$1" "$2" >/dev/null 2>&1 || true
      }
      if [ "$mode" = single ]; then
        # 1-20 plus the named app workspaces. Numbers above 20 are the stubs
        # AeroSpace invents to keep an emptied monitor showing something.
        for ws in $(echo "$where" | cut -d'|' -f1); do
          case "$ws" in
            *[!0-9]*) move "$ws" "$external" ;;
            *) if [ "$ws" -le 20 ]; then move "$ws" "$external"; fi ;;
          esac
        done
        aerospace focus-monitor "$external" >/dev/null 2>&1 || true
      else
        for n in $(seq 1 10); do move "$n" "$builtin"; done
        for n in $(seq 11 20); do move "$n" "$external"; done
      fi
      # Refocus what was focused, unless it was one of those >20 stubs.
      case "$focused" in
        "") ;;
        *[!0-9]*) aerospace workspace "$focused" >/dev/null 2>&1 || true ;;
        *) if [ "$focused" -le 20 ]; then aerospace workspace "$focused" >/dev/null 2>&1 || true; fi ;;
      esac
      [ "$cmd" = apply ] || notify "$(label)"
    '';
  };

  # move-smart <left|down|up|right> — alt-shift-hjkl, ported from Hyprland's
  # run-command-based-on-type-of-workspace + switch-workspace-to-other-monitor:
  #   on an APP workspace (any non-numeric name: beeper, slack, ...) the whole
  #   workspace moves to the monitor in that direction (wrapping, so the key
  #   works whichever side the external sits on);
  #   on a numbered workspace the window moves, and at the workspace edge it
  #   crosses onto the neighbouring monitor, like Hyprland's movewindow.
  move-smart = pkgs.writeShellApplication {
    name = "move-smart";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      export PATH="${homebrewBin}:$PATH:${systemBin}"
      dir="$1"
      ws=$(aerospace list-workspaces --focused 2>/dev/null || true)
      n=$(aerospace list-monitors --count 2>/dev/null || echo 1)
      case "$ws" in
        *[!0-9]*)
          if [ "$n" -ge 2 ]; then
            aerospace move-workspace-to-monitor "$dir" >/dev/null 2>&1 \
              || aerospace move-workspace-to-monitor --wrap-around next >/dev/null 2>&1 || true
            exit 0
          fi ;;
      esac
      exec aerospace move --boundaries all-monitors-outer-frame "$dir"
    '';
  };

  # Searchable cheatsheet of every binding in ~/.aerospace.toml (alt-f1).
  keybinds = pkgs.writeShellScriptBin "keybinds" (builtins.readFile ./keybinds.sh);

  focus-app = pkgs.writeShellApplication {
    name = "focus-app";
    runtimeInputs = [pkgs.coreutils pkgs.gawk dwindle-open];
    text = ''
        # focus-app <App Name> [workspace] [-- launch command...]
        # focus-app --title <title-regex> [workspace] -- <launch command...>
        # Port of the laptop focus_app: jump to the app's own workspace; if it has
        # no window, launch it there. Without a workspace: singleton
        # focus-or-launch, splitting the focused window dwindle-style.
        export PATH="${homebrewBin}:$PATH:${systemBin}"
        # ARG PARSING, fixed 2026-09-12. The --title branch used to fall through
        # into the positional block below, so it still consumed an APP NAME it was
        # never given: `focus-app --title tasker -- tasker` ended up with app="--"
        # and ws="tasker", then tried `open -a "--"`. Title mode has no app name,
        # which is the whole point of matching on window title instead.
        title=""
        app=""
        ws=""
        if [ "''${1:-}" = "--title" ]; then
          title="$2"
          shift 2
          # optional workspace, but only if it is not the -- separator
          if [ $# -gt 0 ] && [ "''${1:-}" != "--" ]; then
            ws="$1"
            shift
          fi
        else
          app="''${1:-}"
          ws="''${2:-}"
          if [ $# -ge 2 ]; then shift 2; else shift $#; fi
        fi
        if [ "''${1:-}" = "--" ]; then shift; fi
        if [ -n "$title" ]; then
          id=$(aerospace list-windows --all --format '%{window-id}|%{window-title}' 2>/dev/null \
            | awk -F'|' -v t="$title" 'tolower($2) ~ tolower(t) {print $1; exit}') || id=""
        else
          id=$(aerospace list-windows --all --format '%{window-id}|%{app-name}' 2>/dev/null \
            | awk -F'|' -v a="$app" 'tolower($2)==tolower(a) {print $1; exit}') || id=""
        fi
        if [ -n "$ws" ]; then
          # A window that has strayed off its workspace is brought home BEFORE the
          # switch. Switching first flashed the (empty or foreign) home workspace
          # and then `focus` jumped on to wherever the window really was: ⌃⌥N went
          # notetaker -> 17 on every press (Oops 20260913-175833).
          if [ -n "$id" ]; then
            wws=$(aerospace list-windows --all --format '%{window-id}|%{workspace}' 2>/dev/null \
              | awk -F'|' -v i="$id" '$1==i {print $2; exit}') || wws=""
            if [ -n "$wws" ] && [ "$wws" != "$ws" ]; then
              aerospace move-node-to-workspace --window-id "$id" "$ws" || true
            fi
          fi
          # App workspaces come to the monitor you are on (2026-09-14): Beeper
          # pressed while focused on the external opens THERE, not back on the
          # laptop where its workspace was born. Numbered ones keep their place.
          case "$ws" in
            *[!0-9]*) aerospace summon-workspace "$ws" || aerospace workspace "$ws" || true ;;
            *) aerospace workspace "$ws" || true ;;
          esac
          if [ -n "$id" ]; then
            exec aerospace focus --window-id "$id"
          elif [ $# -gt 0 ]; then
            exec "$@"
          else
            if [ -n "$app" ]; then exec open -a "$app"; fi
      echo "focus-app: nothing to launch (title mode needs -- <command>)" >&2; exit 1
          fi
        else
          if [ -n "$id" ]; then
            exec aerospace focus --window-id "$id"
          elif [ $# -gt 0 ]; then
            exec dwindle-open "$@"
          else
            if [ -n "$app" ]; then exec dwindle-open open -a "$app"; fi
      echo "focus-app: nothing to launch (title mode needs -- <command>)" >&2; exit 1
          fi
        fi
    '';
  };
}
