# System-Wide Focus — per-device FAIL-OPEN watchdog.
#
# Hard requirement (Matt): if the home server ever stops or dies, the device must use
# the internet as normal. Single-nameserver=blocky gives strict blocking with no leak,
# but is fail-CLOSED on its own. This watchdog restores fail-open WITHOUT reintroducing
# the multi-nameserver leak: it runs LOCALLY on each device (so it works precisely when
# the server is unreachable) and toggles Tailscale's accept-dns.
#
#   blocky reachable  -> `tailscale set --accept-dns=true`   (route through blocky, blocking ON)
#   blocky unreachable-> `tailscale set --accept-dns=false`  (fall back to normal DNS, internet works)
#
# A 2-strike debounce avoids flapping on a single dropped packet. Import this on the
# laptop and desktop hosts (NOT the server). Runs as root so `tailscale set` works.
{pkgs, ...}: let
  blockyIp = "100.118.206.104";
  controlDomain = "example.com"; # never blocked; a real answer => blocky is up
  watchdog = pkgs.writeShellScript "focus-failopen-check" ''
    set -u
    STATE_DIR=/var/lib/focus-failopen
    FAILS_FILE="$STATE_DIR/consecutive_fails"
    mkdir -p "$STATE_DIR"
    fails=$(cat "$FAILS_FILE" 2>/dev/null || echo 0)

    # blocky up iff it returns a real answer for a never-blocked control domain.
    if [ -n "$(${pkgs.dnsutils}/bin/dig +short +timeout=2 +tries=1 @${blockyIp} ${controlDomain} A 2>/dev/null)" ]; then
      echo 0 > "$FAILS_FILE"
      # ensure blocking is ON (only call set if currently off, to avoid churn)
      if [ "$(${pkgs.tailscale}/bin/tailscale debug prefs 2>/dev/null | ${pkgs.jq}/bin/jq -r .CorpDNS 2>/dev/null)" != "true" ]; then
        ${pkgs.tailscale}/bin/tailscale set --accept-dns=true && echo "$(date -Is) blocky up -> accept-dns=true (blocking ON)"
      fi
    else
      fails=$((fails + 1))
      echo "$fails" > "$FAILS_FILE"
      # fail OPEN after 2 consecutive misses (blocky/server/tailscale unreachable)
      if [ "$fails" -ge 2 ]; then
        if [ "$(${pkgs.tailscale}/bin/tailscale debug prefs 2>/dev/null | ${pkgs.jq}/bin/jq -r .CorpDNS 2>/dev/null)" != "false" ]; then
          ${pkgs.tailscale}/bin/tailscale set --accept-dns=false && echo "$(date -Is) blocky DOWN -> accept-dns=false (fail-open, normal DNS)"
        fi
      fi
    fi
  '';
in {
  systemd.services.focus-failopen-watchdog = {
    description = "System-Wide Focus fail-open watchdog (revert to normal DNS if blocky is unreachable)";
    after = ["network.target" "tailscaled.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${watchdog}";
    };
  };
  systemd.timers.focus-failopen-watchdog = {
    description = "Run the fail-open watchdog every 90s";
    wantedBy = ["timers.target"];
    timerConfig = {
      # 90s (2-strike debounce) => internet auto-restores within ≤3min if the
      # server/blocky dies. Halves the dig+tailscale+jq forks vs the old 45s.
      OnBootSec = "60s";
      OnUnitActiveSec = "90s";
      Persistent = true;
    };
  };
}
