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
          # RTX 3060 (12 GB) is shared with second-brain-search's ingest job (~3.75 GB).
          # int8_float16 ~halves the model's VRAM (negligible accuracy loss on Ampere)
          # and expandable_segments avoids fragmentation OOMs — both fix the intermittent
          # "CUDA failed with error out of memory" 500s the STT client was hitting.
          WHISPER__COMPUTE_TYPE = "int8_float16";
          PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
        };
      };
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/fws/cache 0755 root root -"
  ];
}
