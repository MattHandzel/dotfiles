# System-Wide Focus — sanctioned, auto-expiring pause (`focus-pause`).
#
# The anti-self-sabotage problem: if the only way to get past blocking is to defeat
# the system (remove the nameserver, kill the watchdog), the lower self will do exactly
# that — and then "forget to turn it back on". So we give a LEGITIMATE escape hatch that
# auto-expires, removing the incentive to nuke the whole thing.
#
# Design laws honoured:
#   - Lives on the SERVER (behind Tailscale SSH) → costs more than the impulse.
#   - Auto-expires (max 120 min) → can't be left off and forgotten.
#   - Lifts ONLY the calendar-driven focus list. The 24/7 always-list (infiniteworlds,
#     etc.) and the DoH block STAY — pausing is for "I need YouTube for a work reference
#     right now", not for unblocking your hard commitments.
#
# Usage (over SSH to the server):
#   focus-pause           # pause focus blocking for 30 min
#   focus-pause 45        # pause for 45 min (capped at 120)
#   focus-pause status    # how much pause is left
#   focus-pause off       # resume blocking immediately
{pkgs, ...}: let
  pauseFile = "/var/lib/focus-dns/pause-until";
  focusPause = pkgs.writeShellScriptBin "focus-pause" ''
    set -euo pipefail
    PAUSE_FILE=${pauseFile}
    MAX=120
    arg="''${1:-30}"

    case "$arg" in
      status)
        if [ -f "$PAUSE_FILE" ]; then
          until=$(cat "$PAUSE_FILE")
          now=$(date -u +%s); end=$(date -u -d "$until" +%s 2>/dev/null || echo 0)
          left=$(( (end - now) / 60 ))
          if [ "$left" -gt 0 ]; then echo "paused — ''${left} min left (until $until)"; else echo "not paused (stale file)"; fi
        else
          echo "not paused"
        fi
        exit 0 ;;
      off|resume|0)
        rm -f "$PAUSE_FILE"
        echo "resumed — focus blocking is back on within ~60s"
        exit 0 ;;
    esac

    case "$arg" in
      *[!0-9]*) echo "usage: focus-pause [minutes|status|off]"; exit 1 ;;
    esac
    mins=$arg
    [ "$mins" -gt "$MAX" ] && { echo "capped at $MAX min (you asked $mins)"; mins=$MAX; }

    until=$(date -u -d "+''${mins} min" -Is)
    echo "$until" > "$PAUSE_FILE"
    echo "paused focus blocking for ''${mins} min (auto-resumes at $until)"
    echo "takes effect within ~60s. always-list + DoH block stay on. 'focus-pause off' to resume early."
  '';
in {
  environment.systemPackages = [focusPause];

  # Seed the dir (focus-dns.nix already does this, but be self-sufficient if loaded alone).
  systemd.tmpfiles.rules = [
    "d /var/lib/focus-dns 0755 matth users -"
  ];
}
