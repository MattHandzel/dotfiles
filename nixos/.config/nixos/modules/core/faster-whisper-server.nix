{pkgs, ...}: {
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
        ];
        # Expose NVIDIA GPUs via CDI (Docker 25+ recommended)
        extraOptions = [
          "--device=nvidia.com/gpu=all"
        ];
        # Optional: be explicit about bind address/port inside container
        environment = {
          UVICORN_HOST = "0.0.0.0";
          UVICORN_PORT = "8000";
          # Optionally set a default model:
          FWS_DEFAULT_MODEL = "Systran/faster-distil-whisper-large-v3";
        };
      };
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/fws/cache 0755 root root -"
  ];
}
