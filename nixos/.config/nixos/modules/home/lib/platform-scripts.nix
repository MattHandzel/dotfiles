# The six primitives every one of Matt's ~85 scripts actually needs from the
# desktop, with one implementation per platform.
#
# The scripts themselves are shared verbatim between Linux and macOS. Rather
# than fork them, they call these names — and on darwin `compat-shims.nix`
# additionally installs them under their Wayland names (wl-copy, notify-send,
# xdg-open, wtype, fuzzel), so a script that already says `wl-copy` keeps
# working unmodified.
{pkgs}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin;
  bin = pkgs.writeShellScriptBin;
in {
  # stdin -> system clipboard
  clip-copy =
    if isDarwin
    then bin "clip-copy" ''exec /usr/bin/pbcopy "$@"''
    else bin "clip-copy" ''exec ${pkgs.wl-clipboard}/bin/wl-copy "$@"'';

  # system clipboard -> stdout. `--type image/png` (or -t) yields the image.
  # `-p` / `--primary` is Wayland's "currently highlighted text"; macOS has no
  # primary selection, so the darwin build asks the Accessibility API for the
  # focused element's AXSelectedText (works in native apps and Zen/Firefox;
  # Electron apps usually return nothing, in which case this exits 1 like
  # wl-paste -p does with an empty selection).
  clip-paste =
    if isDarwin
    then
      bin "clip-paste" ''
        primary=0
        for a in "$@"; do
          case "$a" in
            image/png | *image*)
              exec ${pkgs.pngpaste}/bin/pngpaste -
              ;;
            -p | --primary) primary=1 ;;
          esac
        done
        if [ "$primary" = 1 ]; then
          sel=$(/usr/bin/osascript -e 'tell application "System Events"' \
            -e 'set p to first process whose frontmost is true' \
            -e 'try' \
            -e 'return value of attribute "AXSelectedText" of (value of attribute "AXFocusedUIElement" of p)' \
            -e 'on error' \
            -e 'return ""' \
            -e 'end try' \
            -e 'end tell' 2>/dev/null)
          [ -n "$sel" ] || exit 1
          printf '%s' "$sel"
          exit 0
        fi
        exec /usr/bin/pbpaste
      ''
    else bin "clip-paste" ''exec ${pkgs.wl-clipboard}/bin/wl-paste "$@"'';

  # notify <title> [body]
  notify =
    if isDarwin
    then
      bin "notify" ''
        title="''${1:-Notification}"
        shift || true
        exec ${pkgs.terminal-notifier}/bin/terminal-notifier -title "$title" -message "$*"
      ''
    else
      bin "notify" ''
        title="''${1:-Notification}"
        shift || true
        exec ${pkgs.libnotify}/bin/notify-send "$title" "$*"
      '';

  # open a file, directory or URL with the desktop default
  open-it =
    if isDarwin
    then bin "open-it" ''exec /usr/bin/open "$@"''
    else bin "open-it" ''exec ${pkgs.xdg-utils}/bin/xdg-open "$@"'';

  # newline-separated choices on stdin -> the picked line on stdout
  pick =
    if isDarwin
    then bin "pick" ''exec ${pkgs.choose-gui}/bin/choose "$@"''
    else bin "pick" ''exec ${pkgs.fuzzel}/bin/fuzzel --dmenu "$@"'';

  # type-text — synthesise keystrokes into the focused app. Speaks wtype's
  # argument grammar so scripts that say `wtype -M ctrl -k v -m ctrl`,
  # `wtype -M ctrl "v"`, `wtype -` (stdin) or `wtype -- "text"` work unchanged:
  #   -M mod / -m mod   press / release a modifier (ctrl → command on macOS,
  #                     because that is where paste/copy/undo live)
  #   -k key            tap a named key (Return, Tab, space, v, …)
  #   -P key / -p key   press / release a key (treated as a tap)
  #   -s ms             sleep
  #   -                 type stdin
  #   anything else     type it literally (with the held modifiers, if any)
  type-text =
    if isDarwin
    then
      bin "type-text" ''
        osa() { /usr/bin/osascript "$@" >/dev/null; }
        mods=()
        mod_clause() {
          [ ''${#mods[@]} -gt 0 ] || { printf ""; return; }
          local joined=""
          for m in "''${mods[@]}"; do joined+="''${joined:+, }''${m} down"; done
          printf ' using {%s}' "$joined"
        }
        map_mod() {
          case "$1" in
            ctrl | control | logo | super | win | cmd | command) echo command ;;
            alt | option) echo option ;;
            shift) echo shift ;;
            *) echo "$1" ;;
          esac
        }
        push_mod() { mods+=("$(map_mod "$1")"); }
        pop_mod() {
          local want; want="$(map_mod "$1")"; local out=()
          for m in "''${mods[@]}"; do [ "$m" = "$want" ] || out+=("$m"); done
          mods=("''${out[@]}")
        }
        type_string() {
          # argv, not interpolation: quotes/backslashes in the text stay literal.
          osa -e 'on run argv' -e "tell application \"System Events\" to keystroke (item 1 of argv)$(mod_clause)" -e 'end run' -- "$1"
        }
        tap_key() {
          local k="$1" code=""
          case "$(printf %s "$k" | tr '[:upper:]' '[:lower:]')" in
            return | enter | kp_enter) code=36 ;;
            tab) code=48 ;;
            space) code=49 ;;
            backspace) code=51 ;;
            escape | esc) code=53 ;;
            delete) code=117 ;;
            left) code=123 ;; right) code=124 ;; down) code=125 ;; up) code=126 ;;
            home) code=115 ;; end) code=119 ;; page_up | prior) code=116 ;; page_down | next) code=121 ;;
          esac
          if [ -n "$code" ]; then
            osa -e "tell application \"System Events\" to key code $code$(mod_clause)"
          else
            type_string "$k"
          fi
        }
        while [ $# -gt 0 ]; do
          case "$1" in
            -M) push_mod "$2"; shift 2 ;;
            -m) pop_mod "$2"; shift 2 ;;
            -k | -P | -p) tap_key "$2"; shift 2 ;;
            -s) sleep "$(awk "BEGIN{print $2/1000}")"; shift 2 ;;
            -d) shift 2 ;; # inter-key delay: ignored
            -) type_string "$(cat)"; shift ;;
            --) shift; [ $# -gt 0 ] && type_string "$*"; break ;;
            *)
              if [ ''${#mods[@]} -gt 0 ] && [ ''${#1} -eq 1 ]; then tap_key "$1"; else type_string "$1"; fi
              shift ;;
          esac
        done
      ''
    else bin "type-text" ''exec ${pkgs.wtype}/bin/wtype "$@"'';
}
