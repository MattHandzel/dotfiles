{
  pkgs,
  inputs,
  username,
  host,
  ...
}: {
  imports = [
    (import ./bootloader.nix)
    (import ./hardware.nix)
    (import ./faster-whisper-server.nix)
    (import ./network.nix)
    (import ./program.nix)
    (import ./security.nix)
    (import ./system.nix)
    (import ./user.nix)
    (import ./services-server.nix)
    (import ./virtualization-server.nix)
    (import ./second-brain-search.nix)
    (import ./text-to-speech-service.nix)
    (import ./life-scheduler.nix)
    # Canary is intentionally not imported here; Faster Whisper is the default STT service.
    (import ./nginx.nix)
    (import ./firefly-iii.nix)
    (import ./freshrss.nix)
    (import ./silverbullet.nix)
    (import ./obsidian-mcp.nix)
    (import ./ntfy-scheduler.nix)
    (import ./ntfy-capture-listener.nix)
    (import ./taskchampion-sync-server.nix)
    (import ./notify-poller.nix)
    (import ./self-improve-watchdog.nix) # MAT-120 dead-man's-switch (watchdog hourly + weekly digest)
    (import ./self-improve-pipeline.nix) # MAT-61 self-improvement automation (weekly mistake-mining + daily enricher)
    (import ./focus-dns.nix)
    (import ./focus-mode-resolver.nix)
    (import ./focus-nameserver-watchdog.nix)
    (import ./focus-pause.nix)
    (import ./self-improve-pipeline.nix)
    (import ./linear-vault-attachments.nix) # MAT-438 auto-attach vault docs referenced in Linear issues (30-min sweep)
  ];

  virtualisation.docker.enable = true;
}
