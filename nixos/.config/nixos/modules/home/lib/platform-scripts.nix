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
  clip-paste =
    if isDarwin
    then
      bin "clip-paste" ''
        for a in "$@"; do
          case "$a" in
            image/png | *image*)
              exec ${pkgs.pngpaste}/bin/pngpaste -
              ;;
          esac
        done
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

  # type-text <string> — synthesise keystrokes into the focused app
  type-text =
    if isDarwin
    then
      bin "type-text" ''
        text="$*"
        # AppleScript string escaping: backslash and double quote.
        esc=''${text//\\/\\\\}
        esc=''${esc//\"/\\\"}
        exec /usr/bin/osascript -e "tell application \"System Events\" to keystroke \"$esc\""
      ''
    else bin "type-text" ''exec ${pkgs.wtype}/bin/wtype "$@"'';
}
