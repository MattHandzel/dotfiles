# exocortex-dashboard.nix — NixOS module (MAT-113). Serves the exocortex birds-eye dashboard
# on the tailnet, regenerated on a timer.
#
# Moved from projects/exocortex-dashboard/deploy/ into the server config by the MAT-113 worker
# (2026-06-03), with ONE correction vs. the original proposal: the serving path is **nginx
# (tailnet-only)** instead of `tailscale serve --https=443`. Reason: this server's nginx already
# binds 0.0.0.0:443 (the reading-list ACME vhost), so `tailscale serve --https=443` would fail to
# bind the tailnet IP's :443. The original tailscale-serve approach is preserved (commented) at the
# bottom as the clean-HTTPS option, should you want to wire a cert later.
#
# What it does, end to end:
#   1. A systemd timer re-runs the aggregator + regenerates the static HTML every 2 minutes
#      (the "build-then-abandon" defense from the research — automation, not manual refresh),
#      publishing it atomically into a world-readable dir (/var/lib/exocortex-dashboard).
#   2. nginx serves that dir on port 8137, exposed ONLY on the tailscale0 interface (firewall),
#      so it is reachable tailnet-only at  http://matts-server.tail01a272.ts.net:8137/
#      and from nowhere public. (Tailnet transport is WireGuard-encrypted, so plain HTTP is fine.)
#
# HOW IT IS WIRED IN: imported from hosts/server/default.nix. This is a NixOS change → Matt reviews
# and runs the staged safe-rebuild (scripts/nixos-safe-rebuild.sh). Tunables are at the top.

{ config, lib, pkgs, ... }:

let
  user       = "matth";
  group      = "users";
  vaultDir   = "/home/matth/Obsidian/Main";
  appDir     = "${vaultDir}/projects/exocortex-dashboard";
  outDir     = "/var/lib/exocortex-dashboard";   # world-readable publish dir (StateDirectory)
  port       = 8137;                             # tailnet-only static port served by nginx
  refreshSec = 120;                              # regenerate cadence (matches HTML meta-refresh)

  # Runtime deps the providers need on PATH (jq/fd/rg/git/systemd + coreutils + bash + tailscale).
  runtimePath = lib.makeBinPath [
    pkgs.bash pkgs.coreutils pkgs.jq pkgs.fd pkgs.ripgrep pkgs.gnugrep
    pkgs.gawk pkgs.gnused pkgs.git pkgs.systemd pkgs.hostname pkgs.tailscale
  ];
in
{
  # ── 1. Regenerate the dashboard on a timer ───────────────────────────────────────────────
  systemd.services.exocortex-dashboard-render = {
    description = "Regenerate the exocortex birds-eye dashboard (aggregate + render HTML)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      Group = group;
      # Publish dir: systemd creates /var/lib/exocortex-dashboard owned by the service user, 0755.
      StateDirectory = "exocortex-dashboard";
      StateDirectoryMode = "0755";
      WorkingDirectory = appDir;
      Environment = [
        "PATH=${runtimePath}"
        "DASHBOARD_REFRESH_SECONDS=${toString refreshSec}"
        "HOME=/home/${user}"
      ];
      # The linear provider uses scripts/linear/lin → needs the Linear token for full data. Optional:
      # without it the linear panel shows a red "down" tile (fail-loud) and the rest works.
      #   EnvironmentFile = "${vaultDir}/.env";   # or a sops secret
      ExecStart = pkgs.writeShellScript "exocortex-dashboard-render" ''
        set -uo pipefail
        cd ${appDir}
        ${pkgs.bash}/bin/bash ${appDir}/dashboard.sh --html >/dev/null 2>&1 || true
        # publish atomically into the world-readable serve dir
        ${pkgs.coreutils}/bin/install -m0644 ${appDir}/out/dashboard.html        ${outDir}/dashboard.html
        ${pkgs.coreutils}/bin/install -m0644 ${appDir}/out/exocortex-status.json ${outDir}/exocortex-status.json
      '';
    };
  };

  systemd.timers.exocortex-dashboard-render = {
    description = "Regenerate the exocortex dashboard every ${toString refreshSec}s";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "60s";
      OnUnitActiveSec = "${toString refreshSec}s";
      AccuracySec = "10s";
      Unit = "exocortex-dashboard-render.service";
    };
  };

  # ── 2. Serve it tailnet-only via the nginx that already runs on this host ─────────────────
  # A static vhost on :8137. We bind 0.0.0.0 (robust to tailscaled boot-order / IP changes) and let
  # the FIREWALL enforce tailnet-only: 8137 is opened on tailscale0 but NOT in the public
  # allowedTCPPorts, so only tailnet devices can reach it.
  services.nginx.virtualHosts."exocortex-dashboard" = {
    listen = [ { addr = "0.0.0.0"; port = port; } ];
    root = outDir;
    locations."/".index = "dashboard.html";
  };

  # Open 8137 on the tailnet interface only. This list MERGES with the host's existing
  # tailscale0 ports ([80 443 8124]) — it does not replace them.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];

  # ── Alternative serving path: clean HTTPS on the bare tailnet hostname via `tailscale serve` ──
  # NOT used here because nginx already owns 0.0.0.0:443 on this host, so `tailscale serve
  # --https=443` would fail to bind. If you want https://matts-server.tail01a272.ts.net/ (no port),
  # either (a) bind nginx's 443 vhosts to the public IPs only — freeing the tailnet IP:443 for
  # tailscale serve — or (b) provision a tailscale cert and add an nginx forceSSL vhost for
  # matts-server.tail01a272.ts.net. The original proposal, kept for reference:
  #
  #   systemd.services.exocortex-dashboard-web = {
  #     description = "Static web server for the exocortex dashboard (localhost:8137)";
  #     after = [ "exocortex-dashboard-render.service" ];
  #     wantedBy = [ "multi-user.target" ];
  #     serviceConfig = {
  #       User = user; Group = group; WorkingDirectory = outDir;
  #       ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString port} --bind 127.0.0.1";
  #       Restart = "always"; RestartSec = "5s";
  #     };
  #   };
  #   systemd.services.exocortex-dashboard-serve = {
  #     description = "Expose the exocortex dashboard on the tailnet via tailscale serve";
  #     after = [ "tailscaled.service" "exocortex-dashboard-web.service" ];
  #     wants = [ "tailscaled.service" ];
  #     wantedBy = [ "multi-user.target" ];
  #     serviceConfig = {
  #       Type = "oneshot"; RemainAfterExit = true;
  #       ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=443 http://127.0.0.1:${toString port}";
  #       ExecStop  = "${pkgs.tailscale}/bin/tailscale serve --https=443 off";
  #     };
  #   };
}
