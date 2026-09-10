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
  # Shared, interception-proof reachability probe (exit 0 = blocky genuinely up).
  # A bare `dig @blocky` is NOT sufficient — see focus-blocky-probe.nix for why.
  blockyProbe = import ./focus-blocky-probe.nix {inherit pkgs;};
  watchdog = pkgs.writeShellScript "focus-failopen-check" ''
    set -u
    STATE_DIR=/var/lib/focus-failopen
    FAILS_FILE="$STATE_DIR/consecutive_fails"
    mkdir -p "$STATE_DIR"
    fails=$(cat "$FAILS_FILE" 2>/dev/null || echo 0)

    # If tailscaled isn't up there is no accept-dns to toggle, and every
    # `tailscale` call below exits 1 — which made this unit fail every 90s
    # (verified 2026-08-07: "Failed to connect to local Tailscale daemon ...
    # tailscaled.service not running", repeating). A red unit here is exactly
    # the fail-open path Matt depends on on a plane, so a permanently-red unit
    # hides a real failure. Nothing to do is success, not failure.
    if ! ${pkgs.systemd}/bin/systemctl -q is-active tailscaled.service; then
      echo "tailscaled not running; nothing to toggle"
      exit 0
    fi

    # blocky up iff the control plane says the peer is online AND it answers DNS.
    if ${blockyProbe}; then
      echo 0 > "$FAILS_FILE"
      # ensure blocking is ON (only call set if currently off, to avoid churn)
      if [ "$(${pkgs.tailscale}/bin/tailscale debug prefs 2>/dev/null | ${pkgs.jq}/bin/jq -r .CorpDNS 2>/dev/null)" != "true" ]; then
        ${pkgs.tailscale}/bin/tailscale set --accept-dns=true && echo "$(date -Is) blocky up -> accept-dns=true (blocking ON)" || true
      fi
    else
      fails=$((fails + 1))
      echo "$fails" > "$FAILS_FILE"
      # fail OPEN after 2 consecutive misses (blocky/server/tailscale unreachable)
      if [ "$fails" -ge 2 ]; then
        if [ "$(${pkgs.tailscale}/bin/tailscale debug prefs 2>/dev/null | ${pkgs.jq}/bin/jq -r .CorpDNS 2>/dev/null)" != "false" ]; then
          ${pkgs.tailscale}/bin/tailscale set --accept-dns=false && echo "$(date -Is) blocky DOWN -> accept-dns=false (fail-open, normal DNS)" || true
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
