# modules/core/linear-webhook-receiver.nix — MAT-40 Linear webhook → ntfy push.
#
# Runs the AES repo's linear-webhook-receiver.py as a hardened systemd service on
# matts-server. Linear POSTs an issue/comment event → the receiver verifies it
# (HMAC-SHA256 signature + replay guard + IP allowlist), distills it to a one-line
# JSON, and republishes it to the on-box ntfy topic `linear-webhook` (localhost:8124).
# scripts/linear/watch.sh --ntfy long-polls that topic and wakes the orchestrator the
# instant an event lands — dropping "Matt moved a card → orchestrator reacts" from ≤60s
# (the API poll) to ~1-2s. Single-live-actor model preserved: the receiver only INFORMS.
#
# EXPOSURE (the receiver binds 127.0.0.1 — a public ingress wrapper is needed):
#   * Matt's pick (2026-06-02): `tailscale funnel`. After this module is live, run ONCE:
#         tailscale funnel --bg ${toString port}
#     which publishes a public https://<device>.<tailnet>.ts.net/ that proxies inbound to
#     this port. The Linear webhook URL is that .ts.net URL. (`tailscale funnel status`
#     to read it; it persists across reboots while the device name is stable.)
#   * Alternative (design doc's recommendation, reuses the LIVE obsidian-mcp pattern): a
#     public nginx vhost. Drop this into nginx.nix and skip funnel:
#         services.nginx.virtualHosts."linear-hook.matthandzel.com" = {
#           enableACME = true; forceSSL = true;
#           locations."/".proxyPass = "http://127.0.0.1:${toString port}";
#         };
#     plus a public DNS A record for linear-hook (matching obsidian-mcp.matthandzel.com).
#   Either path is a Matt-action (funnel toggle OR DNS+rebuild). The service itself is
#   exposure-agnostic — nothing here changes between the two.
#
# SECRET: the Linear webhook signing secret is read from a user-owned EnvironmentFile
# (matts-server has NO sops-nix wired into the flake yet — same pattern as
# notify-poller.nix / tw-linear-bridge.nix). Create it ONCE, mode 0600:
#     mkdir -p /home/matth/.config/linear-webhook-receiver
#     printf 'LINEAR_WEBHOOK_SECRET=%s\n' "<secret-from-Linear-webhookCreate>" \
#       > /home/matth/.config/linear-webhook-receiver/secrets.env
#     chmod 600 /home/matth/.config/linear-webhook-receiver/secrets.env
#   When sops-nix lands (MAT-54 / G4), swap EnvironmentFile for a
#     sops.secrets."linear-webhook/signing-secret"
#   declaration — that one-line swap satisfies the MAT-40 "secret in sops" acceptance.
#   The secret is NEVER logged (the receiver redacts; journald only sees accept/reject).
{ pkgs, ... }:
let
  user = "matth";
  repo = "/home/${user}/Projects/agent-execution-system";
  receiver = "${repo}/scripts/linear/linear-webhook-receiver.py";
  envFile = "/home/${user}/.config/linear-webhook-receiver/secrets.env";
  port = 8131;          # 127.0.0.1 only; the funnel/vhost wrapper faces the public side
  ntfyTopic = "linear-webhook";
in
{
  systemd.services.linear-webhook-receiver = {
    description = "MAT-40: Linear webhook receiver → on-box ntfy push (instant orchestrator wake)";
    after = [ "network.target" "ntfy-sh.service" ];
    wants = [ "ntfy-sh.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.python3 pkgs.coreutils ];

    environment = {
      HOME = "/home/${user}";
      RECEIVER_PORT = toString port;
      NTFY_SERVER = "http://localhost:8124";   # on-box ntfy (never the external hostname)
      NTFY_TOPIC = ntfyTopic;
      TEAM_KEY = "MAT";
      REPLAY_WINDOW_MS = "60000";
      IP_ALLOWLIST_ENFORCE = "1";              # Linear egress allowlist (defense-in-depth)
    };

    serviceConfig = {
      Type = "simple";
      User = user;
      Group = "users";
      # The signing secret arrives ONLY via this file — not in the nix store, not in env
      # declared above. Service refuses to start (exit 2) if the secret is empty.
      EnvironmentFile = envFile;
      ExecStart = "${pkgs.python3}/bin/python3 ${receiver}";
      Restart = "on-failure";
      RestartSec = "10s";

      # ── filesystem + privilege hardening (mirrors notify-poller.nix) ──
      ProtectSystem = "strict";
      ProtectHome = "read-only";   # reads the receiver script + the env file; writes nothing
      PrivateTmp = true;
      NoNewPrivileges = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictNamespaces = true;
      SystemCallArchitectures = "native";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];

      MemoryMax = "128M";
      CPUQuota = "50%";

      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "linear-webhook-receiver";
    };
  };
}
