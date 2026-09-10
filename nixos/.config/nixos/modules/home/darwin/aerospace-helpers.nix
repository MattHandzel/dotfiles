# The two launch helpers behind the AeroSpace app hotkeys (aerospace.nix):
#
#   focus-app     — the macOS port of the laptop's focus_app: jump to the app's
#                   own workspace and focus its window, or launch it there.
#   dwindle-open  — Hyprland-dwindle feel: split the focused window along its
#                   LONGER side before launching, so the new window lands to
#                   the right of a wide window and below a tall one.
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
      export PATH="${homebrewBin}:$PATH:${systemBin}"
      w=""
      h=""
      read -r w h < <(osascript -e "tell application \"System Events\" to tell (first process whose frontmost is true) to get size of front window" 2>/dev/null | tr -d ",") || true
      n=$(aerospace list-windows --workspace focused 2>/dev/null | wc -l | tr -d " ") || n=0
      if [ "''${n:-0}" -ge 1 ] && [ -n "$w" ] && [ -n "$h" ]; then
        if [ "$w" -ge "$h" ]; then
          aerospace split horizontal >/dev/null 2>&1 || true
        else
          aerospace split vertical >/dev/null 2>&1 || true
        fi
      fi
      exec "$@"
    '';
  };

  focus-app = pkgs.writeShellApplication {
    name = "focus-app";
    runtimeInputs = [pkgs.coreutils pkgs.gawk dwindle-open];
    text = ''
      # focus-app <App Name> [workspace] [-- launch command...]
      # focus-app --title <title-regex> <workspace> -- <launch command...>
      # Port of the laptop focus_app: jump to the app's own workspace; if it has
      # no window, launch it there. Without a workspace: singleton
      # focus-or-launch, splitting the focused window dwindle-style.
      export PATH="${homebrewBin}:$PATH:${systemBin}"
      title=""
      if [ "''${1:-}" = "--title" ]; then
        title="$2"
        shift 2
      fi
      app="''${1:-}"
      ws="''${2:-}"
      if [ $# -ge 2 ]; then shift 2; else shift $#; fi
      if [ "''${1:-}" = "--" ]; then shift; fi
      if [ -n "$title" ]; then
        id=$(aerospace list-windows --all --format '%{window-id}|%{window-title}' 2>/dev/null \
          | awk -F'|' -v t="$title" 'tolower($2) ~ tolower(t) {print $1; exit}') || id=""
      else
        id=$(aerospace list-windows --all --format '%{window-id}|%{app-name}' 2>/dev/null \
          | awk -F'|' -v a="$app" 'tolower($2)==tolower(a) {print $1; exit}') || id=""
      fi
      if [ -n "$ws" ]; then
        aerospace workspace "$ws" || true
        if [ -n "$id" ]; then
          exec aerospace focus --window-id "$id"
        elif [ $# -gt 0 ]; then
          exec "$@"
        else
          exec open -a "$app"
        fi
      else
        if [ -n "$id" ]; then
          exec aerospace focus --window-id "$id"
        elif [ $# -gt 0 ]; then
          exec dwindle-open "$@"
        else
          exec dwindle-open open -a "$app"
        fi
      fi
    '';
  };
}
