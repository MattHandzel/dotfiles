# Kokoro-82M text-to-speech, on the server's GPU.
#
# The existing text-to-speech-service (Piper, :47773) stays put — it is fine for
# short notifications — but Piper's flat cadence is unbearable over a 3000-word
# article. Kokoro is the current best open-weights TTS for natural prosody, and
# kokoro-fastapi exposes it behind the OpenAI /v1/audio/speech dialect, so
# read-aloud speaks to either backend without caring which is running.
#
# Container rather than a nixpkgs derivation: Kokoro is not packaged, and the
# upstream image already carries the model weights + ONNX/torch CUDA stack. Same
# pattern as canary-stt-server.nix.
{...}: let
  port = 8880;
in {
  virtualisation.oci-containers.containers.kokoro-tts = {
    # cu126, not cu128: it tolerates older drivers, and Kokoro-82M is small enough
    # that the newer CUDA buys nothing here.
    image = "ghcr.io/remsky/kokoro-fastapi-gpu:v0.6.0-cu126-amd64";
    autoStart = true;
    ports = ["${toString port}:8880"];
    environment = {
      "NVIDIA_VISIBLE_DEVICES" = "all";
      "NVIDIA_DRIVER_CAPABILITIES" = "compute,utility";
    };
    extraOptions = [
      "--device=nvidia.com/gpu=all"
    ];
  };

  # Tailscale-only. This is a plain HTTP endpoint with no auth — it has no business
  # being reachable from the LAN, let alone the internet.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [port];
}
