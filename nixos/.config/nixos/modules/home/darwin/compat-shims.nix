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
  # BSD pkill/pgrep stop reading options at the first pattern; the GNU ones
  # read them anywhere. So the Linux habit `pkill -f 'pat' -U $(id -u)` makes
  # "-U" and "501" two MORE patterns here, and with -f every process whose
  # command line contains either is signalled: Chromium's --lang=en-US hits
  # every Electron/Chrome helper, plus Karabiner-Console-User-Server. An agent
  # did exactly that twice on 2026-10-06 (~50 processes, "things keep
  # crashing", problem log 11:21). Put the options first, the way GNU reads
  # them, and leave the patterns untouched.
  gnuArgOrder = name:
    bin name ''
      opts=() pats=() moved=()
      is_signal() {
        [[ $1 =~ ^-([0-9]+|([Ss][Ii][Gg])?(HUP|INT|QUIT|ILL|TRAP|ABRT|EMT|FPE|KILL|BUS|SEGV|SYS|PIPE|ALRM|TERM|URG|STOP|TSTP|CONT|CHLD|TTIN|TTOU|IO|XCPU|XFSZ|VTALRM|PROF|WINCH|INFO|USR1|USR2|hup|int|quit|kill|term|stop|cont|usr1|usr2))$ ]]
      }
      # BSD pkill only takes -signal as the very first argument.
      if [ ${name} = pkill ] && [ $# -gt 0 ] && is_signal "$1"; then
        opts+=("$1")
        shift
      fi
      while [ $# -gt 0 ]; do
        a=$1
        shift
        case $a in
          --)
            pats+=("$@")
            break
            ;;
          -?*)
            if [ ''${#pats[@]} -gt 0 ]; then moved+=("$a"); fi
            if [ ${name} = pkill ] && is_signal "$a"; then
              opts=("$a" "''${opts[@]}")
            else
              opts+=("$a")
            fi
            if [[ $a == -[FGPUdgtu] ]] && [ $# -gt 0 ]; then
              opts+=("$1")
              if [ ''${#pats[@]} -gt 0 ]; then moved+=("$1"); fi
              shift
            fi
            ;;
          *) pats+=("$a") ;;
        esac
      done
      if [ ''${#moved[@]} -gt 0 ]; then
        echo "${name}: treating ''${moved[*]} as options, not patterns (macOS ${name} wants options before the pattern)" >&2
      fi
      exec /usr/bin/${name} "''${opts[@]}" -- "''${pats[@]}"
    '';
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
    (gnuArgOrder "pkill")
    (gnuArgOrder "pgrep")
  ];
}
