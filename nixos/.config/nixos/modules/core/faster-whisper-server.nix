{pkgs, ...}: let
  patchDir = "/home/matth/dotfiles/nixos/.config/nixos/modules/core/faster-whisper-server-patches";
in {
  virtualisation = {
    oci-containers = {
      containers.faster-whisper-server = {
        autoStart = true;
        image = "fedirz/faster-whisper-server:latest-cuda";
        # Map host 42001 -> container 8000 (faster-whisper-server default)
        ports = ["47770:8000"];
        # Persist models/cache to avoid re-downloads
        volumes = [
          "/var/lib/fws/cache:/root/.cache/huggingface"
          "${patchDir}/stt.py:/root/faster-whisper-server/faster_whisper_server/routers/stt.py:ro"
          "${patchDir}/asr.py:/root/faster-whisper-server/faster_whisper_server/asr.py:ro"
          # Expose NVIDIA GPUs via CDI (Docker 25+ recommended)
        ];
        extraOptions = [
          "--device=nvidia.com/gpu=all"
        ];
        # Optional: be explicit about bind address/port inside container
        environment = {
          UVICORN_HOST = "0.0.0.0";
          UVICORN_PORT = "8000";
          DEFAULT_LANGUAGE = "en";
          WHISPER__MODEL = "Systran/faster-distil-whisper-large-v3";
        };
      };
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/fws/cache 0755 root root -"
  ];
}
