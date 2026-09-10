# System-Wide Focus — shared "is blocky actually reachable?" probe.
#
# Exit 0 = the focus resolver on the server is genuinely reachable.
# Exit 1 = it is not, and the caller should fail OPEN (normal DNS, internet works).
#
# WHY THIS EXISTS (2026-09-09). Both fail-open paths — focus-failopen-watchdog.nix and
# captive-portal.nix — used to decide this with a bare
#     dig +short @100.118.206.104 example.com A
# and treat any non-empty answer as "blocky is up". That is not sound. Plenty of
# networks (hotel, airline, some ISPs/routers) transparently intercept every UDP :53
# packet and answer it themselves regardless of the destination IP. On such a network
# the probe ALWAYS succeeds — even with the server powered off.
#
# Observed here: matts-server had been offline for 13 days (Tailscale last-seen
# 2026-08-27) and `dig @100.118.206.104 example.com` still returned two A records with
# the `aa` flag set. So the watchdog concluded "blocky is up" and re-asserted
# `accept-dns=true` every 90s. The moment Tailscale came up, DNS was pointed at a dead
# host and the whole machine lost name resolution — the exact fail-CLOSED outcome these
# modules exist to prevent.
#
# The fix is to ask something an interceptor cannot forge: the Tailscale coordination
# server's own view of whether the peer is online. That answer arrives over an
# authenticated control channel, not over :53. The dig is kept as a second gate so a
# live host with a dead blocky process still fails open.
{pkgs}:
pkgs.writeShellScript "focus-blocky-probe" ''
  set -u
  BLOCKY_IP=100.118.206.104
  CONTROL_DOMAIN=example.com

  ts=${pkgs.tailscale}/bin/tailscale
  jq=${pkgs.jq}/bin/jq
  dig=${pkgs.dnsutils}/bin/dig

  # Gate 1: Tailscale must be running. The tailnet is the only route to blocky, so if
  # the daemon is down or logged out, blocky is unreachable by definition.
  status=$("$ts" status --json 2>/dev/null) || exit 1
  [ -n "$status" ] || exit 1
  [ "$(printf '%s' "$status" | "$jq" -r '.BackendState' 2>/dev/null)" = "Running" ] || exit 1

  # Gate 2: the control plane must report the blocky peer as online. Unforgeable by a
  # :53 interceptor. Absent/unknown peer => not online => fail open.
  online=$(printf '%s' "$status" \
    | "$jq" -r --arg ip "$BLOCKY_IP" \
        '[.Peer[]? | select((.TailscaleIPs // []) | index($ip)) | .Online] | first // false' \
        2>/dev/null) || exit 1
  [ "$online" = "true" ] || exit 1

  # Gate 3: the host is up — is the resolver process itself answering?
  [ -n "$("$dig" +short +timeout=2 +tries=1 @"$BLOCKY_IP" "$CONTROL_DOMAIN" A 2>/dev/null)" ] || exit 1

  exit 0
''
