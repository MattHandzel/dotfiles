# The ~85 wrapped scripts in modules/home/scripts are shared verbatim between
# the laptop and the Mac. Most of them touch the desktop through exactly six
# Wayland-named commands. Rather than fork every script (85 forks, 85 chances to
# drift), this installs those six NAMES on macOS, backed by the platform
# implementations in ../lib/platform-scripts.nix.
#
# So `wl-copy` on the Mac is pbcopy, `notify-send` is terminal-notifier, and a
# script written for Hyprland runs unmodified. The scripts keep one source of
# truth; only this shim layer knows about the platform.
#
# Deliberately NOT shimmed: hyprctl, wlr-randr, swaync-client, waybar. Those
# have no macOS analogue at all, and the scripts that use them are gated out of
# the darwin build entirely (see modules/home/scripts/scripts.nix `linuxScripts`).
{pkgs, ...}: let
  platform = import ../lib/platform-scripts.nix {inherit pkgs;};
  bin = pkgs.writeShellScriptBin;
in {
  home.packages = [
    (bin "wl-copy" ''exec ${platform.clip-copy}/bin/clip-copy "$@"'')
    (bin "wl-paste" ''exec ${platform.clip-paste}/bin/clip-paste "$@"'')
    (bin "notify-send" ''
      # notify-send's flags (-a/-u/-t/-i/-h) have no terminal-notifier
      # equivalent; drop them and keep the two positional arguments, which is
      # all any of the scripts here actually rely on.
      args=()
      while [ $# -gt 0 ]; do
        case "$1" in
          -a | --app-name | -u | --urgency | -t | --expire-time | -i | --icon | -h | --hint | -c | --category)
            shift 2 || shift
            ;;
          -*) shift ;;
          *)
            args+=("$1")
            shift
            ;;
        esac
      done
      exec ${platform.notify}/bin/notify "''${args[@]}"
    '')
    (bin "xdg-open" ''exec ${platform.open-it}/bin/open-it "$@"'')
    (bin "wtype" ''exec ${platform.type-text}/bin/type-text "$@"'')
    (bin "fuzzel" ''
      # Only the `--dmenu` shape is used by the scripts here; anything else is
      # a launcher invocation, which is Raycast's job on macOS.
      exec ${platform.pick}/bin/pick
    '')
  ];
}
