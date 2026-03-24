{ pkgs, config, ... }:

let
  srcDir = "/home/matth/dotfiles/nixos/.config/nixos/modules/core/canary-stt";
  modelDir = "/var/lib/canary-stt/models";
  cacheDir = "/var/lib/canary-stt/cache";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/canary-stt 0755 root root -"
    "d ${modelDir} 0755 root root -"
    "d ${cacheDir} 0755 root root -"
  ];

  # Using a pre-built image from NVIDIA NGC for absolute stability
  virtualisation.oci-containers.containers.canary-stt = {
    image = "nvcr.io/nvidia/nemo:24.12"; 
    autoStart = true;
    # SWAPPED: Port 47770 is now the primary STT entry point
    ports = [ "47770:47770" ]; 
    volumes = [
      "${modelDir}:/models"
      "${cacheDir}:/root/.cache/torch"
      "${srcDir}/main.py:/app/main.py"
    ];
    environment = {
      "PYTHONPATH" = "/app";
      "CUDA_VISIBLE_DEVICES" = "all";
      "NVIDIA_VISIBLE_DEVICES" = "all";
      "NVIDIA_DRIVER_CAPABILITIES" = "compute,utility,video";
    };
    cmd = [ "python3" "/app/main.py" ];
    extraOptions = [
      "--device=nvidia.com/gpu=all"
      "--ipc=host"
    ];
  };
}
