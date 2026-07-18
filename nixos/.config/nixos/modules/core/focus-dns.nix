# System-Wide Focus — off-device DNS enforcement (blocky), fail-open.
#
# Part of the `system-wide-focus` project (projects/system-wide-focus in the vault).
# This is the un-toggleable core: a DNS resolver on the server that every device
# reaches through Tailscale. The off-switch lives here, not under Matt's thumb.
#
# Design laws (from the project SPEC):
#   1. The kill-switch must cost more than the impulse -> it lives on the server.
#   2. Block the novelty-seeking *category*, not the instance -> category deny-list.
#
# Two deny-list groups, both mutable runtime files the resolver owns and hot-reloads
# via the blocky REST API (POST /api/lists/refresh):
#   - focus  (/var/lib/focus-dns/active-blocklist.txt) — the novelty *category*,
#            written PER MODE by the resolver. Empty unless a Deep Work / Comms block
#            is active (calendar-driven). Seeded empty.
#   - always (/var/lib/focus-dns/always-blocklist.txt) — Matt's personal "never let me
#            on these" list, synced from ~/notes/resources/dns-blocklist.md. Blocked
#            24/7 regardless of mode. Seeded empty; the resolver fills it every run
#            (independent of the calendar token, so it works even before OAuth).
# tmpfiles seeds both files empty; the resolver never has its writes clobbered.
#
# Fail-open: blocky's upstreams are public resolvers. If blocky is UP, a blocked
# domain returns 0.0.0.0 (a *successful* answer, so Linux resolvers do NOT fall back).
# If the SERVER is down, the device's SECOND Tailscale nameserver (a public resolver,
# set in the Tailscale admin console) answers -> internet survives. See SPEC AC#2/AC#3.
#
# FORMAT IS LOAD-BEARING: blocky 0.28+ does NOT block subdomains for a plain
# `youtube.com` entry (verified live: apex blocked, www./m. leaked). The wildcard form
# `*.domain.com` blocks apex AND all subdomains. The resolver emits `*.domain.com`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Mutable, resolver-owned deny-lists. blocky (DynamicUser, ProtectSystem=strict) can
  # READ these (read-only fs still permits reads); the resolver (user matth) WRITES them.
  activeList = "/var/lib/focus-dns/active-blocklist.txt"; # focus group (per-mode)
  alwaysList = "/var/lib/focus-dns/always-blocklist.txt"; # always group (user list)

  # Anti-bypass: block public DNS-over-HTTPS endpoints so a browser's built-in DoH
  # (Firefox/Chrome → Cloudflare/Google) can't silently resolve around blocky. Always
  # on, IMMUTABLE (nix store, not user-editable on-device → can't be quietly disabled).
  # `use-application-dns.net` is Firefox's canary: returning 0.0.0.0 makes Firefox
  # disable its own DoH and fall back to system DNS (= blocky).
  antibypassList = pkgs.writeText "focus-dns-antibypass.txt" ''
    *.cloudflare-dns.com
    *.mozilla.cloudflare-dns.com
    *.chrome.cloudflare-dns.com
    *.dns.google
    *.doh.opendns.com
    *.dns.quad9.net
    *.dns.adguard.com
    *.doh.cleanbrowsing.org
    *.dns.nextdns.io
    use-application-dns.net
  '';

  # ALLOWLIST — never-block exceptions, applied OVER the denylists. blocky checks the
  # allowlist on the QUERIED name and short-circuits before the CNAME-chain denylist
  # check, so this fixes CNAME false-positives the markdown allowlist can't reach.
  #
  # Beeper (Matt 2026-06-02 "beeper on all the time"): api.beeper.com CNAMEs through
  # lb.aws.beeper.com → an *.eu-central-1.amazonaws.com ELB that the 1.37M-domain bulk
  # import catches → blocky returned 0.0.0.0 for api.beeper.com and Beeper died. The
  # blocked entry is an amazonaws domain, not a beeper one, so strip_allowed (which only
  # removes *beeper* domains from the lists) can't help — the queried-name allowlist can.
  allowList = pkgs.writeText "focus-dns-allowlist.txt" ''
    beeper.com
    *.beeper.com
    beeper-tools.com
    *.beeper-tools.com
    stripe.com
    *.stripe.com
  '';
in {
  services.blocky = {
    enable = true;
    # enableConfigCheck defaults true -> `blocky validate` runs at build time.
    settings = {
      # Fail-open upstreams: plain IPs (no bootstrap needed). parallel_best races them.
      upstreams.groups.default = [
        "1.1.1.1"
        "8.8.8.8"
        "9.9.9.9"
      ];

      # DNS on :53 (firewalled to tailscale0 below). HTTP API bound to localhost for
      # the resolver's hot-reload (POST /api/lists/refresh).
      ports = {
        dns = 53;
        http = "127.0.0.1:4000";
      };

      blocking = {
        denylists = {
          focus = [activeList];
          always = [alwaysList];
          antibypass = [antibypassList];
        };
        # Allowlist per group: a beeper query is never blocked by EITHER the 24/7 bulk
        # list (always) or the per-mode list (focus), so Beeper stays up in every mode.
        allowlists = {
          always = [allowList];
          focus = [allowList];
        };
        # focus = mode-driven; always = 24/7 user list; antibypass = 24/7 DoH block.
        clientGroupsBlock.default = ["focus" "always" "antibypass"];
        # zeroIp -> A queries for blocked domains return 0.0.0.0 (SPEC AC#1).
        blockType = "zeroIp";
        # Short block TTL so a mode transition takes effect fast: when Deep Work ends
        # and the resolver clears the focus list, cached 0.0.0.0 answers expire within
        # ~30s instead of lingering for hours (blocky's default is much longer).
        blockTTL = "30s";
        loading = {
          # The resolver pushes immediate reloads via POST /api/lists/refresh on mode
          # transitions; blocky's default periodic refresh stays on as a harmless backstop.
          # `fast` => blocky always starts even if a list source hiccups (fail-open spirit).
          strategy = "fast";
        };
      };

      # Passive measurement (SPEC AC#7): per-day CSV in /var/log/blocky (LogsDirectory).
      # Blocked attempts per client/domain are countable from these with no manual logging.
      queryLog = {
        type = "csv";
        target = "/var/log/blocky";
        logRetentionDays = 14;
      };

      log.level = "info";
    };
  };

  # Create the dir + both deny-list files empty (if absent), owned by matth so the
  # resolver (runs as matth, like ntfy-scheduler) can rewrite them. World-readable for
  # blocky. `f` never truncates an existing file, so resolver writes survive reboots.
  systemd.tmpfiles.rules = [
    "d /var/lib/focus-dns 0755 matth users -"
    "f /var/lib/focus-dns/active-blocklist.txt 0644 matth users -"
    "f /var/lib/focus-dns/always-blocklist.txt 0644 matth users -"
  ];

  # Open DNS only on the Tailscale interface. These lists merge with the existing
  # tailscale0 rules in hosts/server/default.nix (NixOS concatenates list options).
  networking.firewall.interfaces.tailscale0 = {
    allowedUDPPorts = [53];
    allowedTCPPorts = [53];
  };
}
