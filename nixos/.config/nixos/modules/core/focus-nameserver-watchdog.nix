# System-Wide Focus — Tailscale nameserver watchdog (anti-bypass).
#
# The tailnet global nameserver IS the master off-switch: set it to [blocky] and every
# device routes through blocky; remove it and all blocking stops instantly. This server
# timer re-asserts the nameserver to EXACTLY [blocky] every 5 min, so the lower self
# removing it (or adding a second resolver to reintroduce the leak) self-heals.
#
# Fail-open is NOT done by removing the nameserver — it's per-device (accept-dns toggle,
# focus-failopen-watchdog.nix) — so this watchdog and fail-open don't fight.
{pkgs, ...}: let
  desired = "100.118.206.104"; # server's Tailscale IP (blocky)
  script = pkgs.writeShellScript "focus-nameserver-watchdog" ''
    set -u
    ENVFILE=/home/matth/Obsidian/Main/.env
    [ -f "$ENVFILE" ] || { echo "no .env; skip"; exit 0; }
    # Source .env in a subshell so the shell parses the quoting (no hand-rolled stripping).
    KEY=$(set -a; . "$ENVFILE" >/dev/null 2>&1; printf '%s' "$TAILSCALE_API_KEY")
    [ -n "$KEY" ] || { echo "no TAILSCALE_API_KEY; skip"; exit 0; }
    API="https://api.tailscale.com/api/v2/tailnet/-/dns/nameservers"
    CUR=$(${pkgs.curl}/bin/curl -s "$API" -u "$KEY:")
    DNS=$(echo "$CUR" | ${pkgs.jq}/bin/jq -c '.dns' 2>/dev/null)
    if [ "$DNS" != '["${desired}"]' ]; then
      echo "$(date -Is) nameserver drifted: $DNS -> re-applying [${desired}]"
      ${pkgs.curl}/bin/curl -s -X POST "$API" -u "$KEY:" \
        -H "Content-Type: application/json" -d '{"dns":["${desired}"]}' >/dev/null
    fi
  '';
in {
  systemd.services.focus-nameserver-watchdog = {
    description = "Re-assert the focus DNS nameserver if it drifts (anti-bypass)";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      User = "matth";
      ExecStart = "${script}";
    };
  };
  systemd.timers.focus-nameserver-watchdog = {
    description = "Check the tailnet nameserver every 5 min";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "5min";
      Persistent = true;
      Unit = "focus-nameserver-watchdog.service";
    };
  };
}
