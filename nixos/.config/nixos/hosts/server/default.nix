{
  pkgs,
  config,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./../../modules/core/server.nix
    ./../../modules/core/taskwarrior-daily-notify.nix
    ./../../modules/core/exocortex-dashboard.nix
  ];

  nixpkgs.overlays = [
    (final: prev: {
      ollama-cuda =
        (import (builtins.fetchTarball {
            url = "https://github.com/NixOS/nixpkgs/archive/b12141ef619e0a9c1c84dc8c684040326f27cdcc.tar.gz";
            sha256 = "0vhprxh6zqrc8bc745crfzs75cl1sqls3hdldlairm0spqsb88k5";
          }) {
            system = final.system;
            config.allowUnfree = true;
            config.cudaSupport = true;
          })
        .ollama-cuda;
    })
  ];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    openFirewall = true;
    host = "0.0.0.0";
    environmentVariables = {
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_KEEP_ALIVE = "5m";
    };
  };

  services.atuin.enable = true;
  services.second-brain-search.enable = true;
  services.obsidian-mcp.enable = true;
  services.text-to-speech-service.enable = true;
  services.text-to-speech-service.defaultVoice = "en_US-lessac-high";
  services.life-scheduler.enable = true;
  networking.firewall.allowedTCPPorts = [47772];
  networking.hostName = "matts-server";

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  environment.systemPackages = with pkgs; [
    cargo
    rustup
    brightnessctl # Maybe useful for debugging, harmless
    powertop
    cudaPackages.cuda_nvcc
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    # cudaPackages.libcutensor
    gcc13

    # Server Dev Tools
    tailscale
    mosh
    tmux
    git
    ripgrep
    fd
    fzf
    bat
    zoxide
    btop
    direnv
    just
    restic
  ];

  services.syncthing = {
    enable = true;
    user = "matth";
    dataDir = "/home/matth";
    configDir = "/home/matth/.config/syncthing";
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = false;

    settings = {
      devices = {
        "matts-computer" = {id = "QKTFBXV-BQA4F7D-KH665IF-H3O4ZUT-BC5LWMM-BKCLRZX-7P7Y4UA-WFWMMQ3";};
        "Pixel 9a" = {id = "OUXTWJX-MARBGAE-ANVOBSS-ANCZDVY-QGJGWNC-YXK62MC-IPV22XX-PV3RMA5";};
      };
      folders = {
        "sx2ys-nb2px" = {
          # Recordings
          path = "~/notes/capture/raw_capture/audio_recordings/";
          devices = ["matts-computer" "Pixel 9a"];
        };
        "r9mpp-yvvmy" = {
          # Obsidian
          path = "~/Obsidian";
          devices = ["matts-computer" "Pixel 9a"];
        };
        "claude" = {
          # ~/.claude (Claude Code config + memory). MAT-169.
          # Declared so overrideFolders (default true) does NOT prune this
          # imperatively-added folder on rebuild. ignorePatterns mirror the
          # live ~/.claude/.stignore: sync durable config + auto-memory, keep
          # hot append-only runtime state (transcripts, self-improve store)
          # machine-local so Syncthing never sync-conflicts on it.
          path = "~/.claude";
          devices = ["matts-computer"];
          ignorePatterns = [
            "!/.credentials.json"
            "!/projects/**/memory/**" # KEEP auto-memory synced (carve-out first)
            "/projects/**/*.jsonl" # hot session+subagent transcripts (conflict source)
            "/self-improve" # per-host runtime + idempotency store
            "/cache"
            "/shell-snapshots"
            "/file-history"
            "/paste-cache"
            "/session-env"
            "/daemon"
            "/daemon.log"
            "/debug"
            "/telemetry"
            "/backups"
            "/plugins"
            "/jobs"
            "/history.jsonl"
            "/usage-log.jsonl"
            "(?d)*.lock"
            "/.last-cleanup"
            "/.last-update-result.json"
            "/stats-cache.json"
            "/mcp-needs-auth-cache.json"
          ];
        };
      };
    };
  };

  systemd.timers."website-update" = {
    description = "Timer to update the website project";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 00,20:00:00";
      Persistent = true;
    };
  };

  systemd.services."website-update" = {
    description = "Update and push website project";
    serviceConfig = {
      User = "matth";
      Group = "users";
      Type = "oneshot";
      WorkingDirectory = "/home/matth/Projects/website";
    };
    script = with pkgs; ''
      export HOME=/home/matth
      export GIT_AUTHOR_NAME="Matt's Server"
      export GIT_AUTHOR_EMAIL="handzelmatthew@gmail.com"
      export GIT_COMMITTER_NAME="Matt's Server"
      export GIT_COMMITTER_EMAIL="handzelmatthew@gmail.com"

      git pull
      bash ./reset.sh
      git commit -am "Updating website at $(date)"
      git push --no-verify
    '';
  };

  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "performance";
  services.thermald.enable = true;
  zramSwap.enable = true;

  home-manager.backupFileExtension = "backup_$(date +%Y-%m-%d_%H-%M-%S)";

  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "http://server.matthandzel.com:8124";
      listen-http = ":8124";
    };
  };
  services.openssh.enable = true;
  services.tailscale.enable = true;

  networking.firewall.interfaces.tailscale0.allowedUDPPortRanges = [
    {
      from = 60000;
      to = 61000;
    }
  ];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [80 443 8124];
  networking.firewall.interfaces.tailscale0.allowedTCPPortRanges = [
    {
      from = 7180;
      to = 7190;
    }
  ];

  hardware.nvidia-container-toolkit.enable = true;
  hardware.graphics.enable32Bit = true;
}
