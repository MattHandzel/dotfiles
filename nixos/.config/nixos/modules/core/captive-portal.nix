# Captive portals (airplane, hotel, café Wi-Fi) must always just work.
#
# THE REPORT (Matt, 2026-08-07): "whenever I go on an airplane my laptop refuses
# to connect to the network. I think this is because of things being blocked in
# my DNS." Right about the layer — here is the exact mechanism.
#
# ROOT CAUSE 1 — Tailscale takes /etc/resolv.conf EXCLUSIVELY.
#   tailscaled's openresolv manager runs, verbatim from net/dns/openresolv.go:
#       resolvconf -m 0 -x -a tailscale
#   `-x` is openresolv's *exclusive* flag: resolv.conf is rewritten to hold ONLY
#   `nameserver 100.100.100.100`, and the DHCP-supplied resolver is ERASED — not
#   appended after it, erased. (Confirmed on this laptop: `journalctl -u
#   tailscaled` logs `dns: using dns.openresolvManager`.) With accept-dns=true —
#   the normal state, since focus-failopen-watchdog.nix asserts it whenever blocky
#   is reachable — every query is forwarded over the tailnet to blocky on the
#   server at 100.118.206.104.
#
#   On a plane you are behind an *unauthenticated* portal, so the tailnet is
#   unreachable and every DNS query dies. Worse, a captive portal delivers its
#   sign-in page precisely BY hijacking DNS — a query that never reaches the
#   portal's resolver can never be redirected to the sign-in page. Net effect: no
#   name resolution, no sign-in page, no internet, indefinitely.
#
# ROOT CAUSE 2 — NetworkManager's captive-portal detection was switched OFF.
#   Measured on this laptop before this change (busctl get-property on
#   org.freedesktop.NetworkManager):
#       ConnectivityCheckEnabled    false
#       ConnectivityCheckUri        ""
#       ConnectivityCheckAvailable  false
#   nixpkgs builds NetworkManager with no connectivity URI, so NM never probes,
#   never enters the `portal` state, and cheerfully reports CONNECTIVITY=full
#   while behind a portal. Nothing ever says "sign in to this network" — so even
#   once DNS works, finding the portal is guesswork.
#
# THE FIX — three layers:
#   1. Turn NM's connectivity probe on, over plain HTTP, so a portal is DETECTED
#      and NM can actually reach CONNECTIVITY=portal.
#   2. An NM dispatcher script that, on every network event where we do NOT have
#      full connectivity AND blocky is provably unreachable, immediately hands DNS
#      back to the network we are physically attached to (accept-dns=false).
#      focus-failopen-watchdog.nix already does this, but on a two-strike ≤3-minute
#      timer; a portal needs it NOW, on the `up` event, before Matt concludes the
#      Wi-Fi is broken.
#   3. captive-browser: a throwaway Chromium whose name resolution goes through a
#      SOCKS5 proxy pointed at the DHCP-supplied resolver. Immune to blocky, to
#      Tailscale, to the browser's own DoH, and — because the profile is fresh
#      every launch — to the HSTS cache that otherwise upgrades the portal's
#      http:// redirect to https:// and silently breaks the interception. That
#      HSTS upgrade is the single most common reason a portal "doesn't load" even
#      on a machine with perfectly healthy DNS. Auto-launched on portal detection.
#
# THIS IS NOT A FOCUS BYPASS. Nothing here permanently disables focus blocking:
#   - The layer-2 release is gated on blocky being PROVABLY unreachable (a real
#     dig against it fails), not merely on the connectivity probe being unhappy —
#     so a flaky probe at home can't be used as a bypass lever.
#   - The restore is automatic: once Matt signs in, blocky answers again and
#     focus-failopen-watchdog flips accept-dns back to true within 90s.
{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  # Shared "is blocky genuinely reachable?" probe (exit 0 = up). Same probe the
  # fail-open watchdog uses. A bare `dig @blocky` is NOT sufficient: networks that
  # intercept UDP :53 answer it even with the server powered off, which pinned this
  # gate permanently closed. See focus-blocky-probe.nix.
  blockyProbe = import ./focus-blocky-probe.nix {inherit pkgs;};

  # Matt's Wi-Fi interface. captive-browser binds its SOCKS5 proxy to this so it
  # can't collide with a portal's private subnet.
  wifiInterface = "wlp0s20f3";

  # Runs in Matt's graphical session (started by the dispatcher below via
  # `systemctl --user --machine=`). Absolute store paths throughout: the systemd
  # user manager's PATH is NOT Matt's shell PATH — see the hyprland-exec-path
  # lesson in docs/MISTAKES.md.
  signinScript = pkgs.writeShellScript "captive-portal-signin" ''
    ${pkgs.libnotify}/bin/notify-send -u normal -i network-wireless \
      "Wi-Fi needs sign-in" "Opening the captive-portal login page…"
    # Installed into the system profile by programs.captive-browser below.
    exec /run/current-system/sw/bin/captive-browser
  '';

  dispatcher = pkgs.writeShellScript "captive-portal-dispatcher" ''
    set -u

    iface="''${1:-}"
    action="''${2:-}"

    # `connectivity-change` is the portal-detection event; `up`/`dhcp4-change`
    # catch the join itself, which is where the plane case starts.
    case "$action" in
      up | dhcp4-change | connectivity-change) ;;
      *) exit 0 ;;
    esac

    # Tailscale's own interface coming up must not re-enter this, or releasing
    # accept-dns would trigger the event that releases accept-dns.
    case "$iface" in
      tailscale0 | lo) exit 0 ;;
    esac

    nmcli=${pkgs.networkmanager}/bin/nmcli
    ts=${pkgs.tailscale}/bin/tailscale
    jq=${pkgs.jq}/bin/jq
    systemctl=${pkgs.systemd}/bin/systemctl

    conn=$("$nmcli" -t -f CONNECTIVITY general 2>/dev/null || echo unknown)
    if [ "$conn" = "full" ]; then
      exit 0
    fi

    # ---- Layer 2: hand DNS back to the network we are physically attached to ----
    #
    # Only if blocky is PROVABLY unreachable. If blocky answers, DNS is healthy and
    # whatever is wrong with connectivity is not ours to fix by dropping Matt's
    # focus blocking. This gate is what keeps the module from being a bypass.
    if ! ${blockyProbe}; then
      corpdns=$("$ts" debug prefs 2>/dev/null | "$jq" -r .CorpDNS 2>/dev/null || echo unknown)
      if [ "$corpdns" = "true" ]; then
        echo "connectivity=$conn and blocky unreachable -> accept-dns=false (restoring DHCP DNS)"
        "$ts" set --accept-dns=false || true
        # openresolv needs a moment to rewrite /etc/resolv.conf, then re-probe.
        ${pkgs.coreutils}/bin/sleep 2
        "$nmcli" networking connectivity check >/dev/null 2>&1 || true
        conn=$("$nmcli" -t -f CONNECTIVITY general 2>/dev/null || echo unknown)
      fi
    fi

    if [ "$conn" = "full" ]; then
      exit 0
    fi

    # ---- Layer 3: a portal is in front of us — open the sign-in page ----
    if [ "$conn" != "portal" ]; then
      # limited/none with no portal detected: a genuinely dead network (no
      # uplink at all). Nothing to sign into; don't spawn a browser at it.
      exit 0
    fi

    # Debounce: NM re-probes on its own interval, and our own `connectivity check`
    # above emits a connectivity-change. Without this, one join spawns a stack of
    # Chromium windows. /run is tmpfs, so this resets every boot.
    state=/run/captive-portal
    ${pkgs.coreutils}/bin/mkdir -p "$state"
    now=$(${pkgs.coreutils}/bin/date +%s)
    last=$(${pkgs.coreutils}/bin/cat "$state/last-signin" 2>/dev/null || echo 0)
    if [ "$((now - last))" -lt 300 ]; then
      echo "portal detected but sign-in browser was launched $((now - last))s ago; skipping"
      exit 0
    fi
    echo "$now" > "$state/last-signin"

    echo "captive portal detected on $iface -> launching sign-in browser"
    "$systemctl" --user --machine=${username}@.host \
      start captive-portal-signin.service || true
  '';
in {
  # ---- Layer 1: let NetworkManager actually SEE a captive portal ----
  #
  # Plain HTTP on purpose: a portal must be able to intercept and redirect the
  # probe, which it cannot do to an HTTPS request. `response=` is required for
  # this endpoint (it returns a body, not a bare 204). 300s is NM's own default
  # cadence — enough to notice a portal appearing, not a chatty beacon.
  networking.networkmanager.settings.connectivity = {
    uri = "http://nmcheck.gnome.org/check_network_status.txt";
    response = "NetworkManager is online";
    interval = 300;
  };

  networking.networkmanager.dispatcherScripts = [
    {
      source = dispatcher;
      type = "basic";
    }
  ];

  # ---- Layer 3: the sign-in browser ----
  programs.captive-browser = {
    enable = true;
    interface = wifiInterface;
  };

  systemd.user.services.captive-portal-signin = {
    description = "Open the captive-portal sign-in browser";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${signinScript}";
    };
  };
}
