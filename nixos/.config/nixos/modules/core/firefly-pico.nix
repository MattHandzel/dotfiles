{
  pkgs,
  lib,
  config,
  ...
}: let
  # Firefly Pico -- mobile-optimised companion UI for Firefly III.
  # https://github.com/cioraneanu/firefly-pico  (AGPL-3.0, ~950 stars, actively developed)
  #
  # Firefly III's own web UI is poor on a phone, which is exactly where expenses get
  # entered. Pico is the community's answer: fast entry, templates, subtags.
  #
  # Served on the tailnet only. It deliberately does NOT get its own public hostname or
  # certificate yet -- that would chain onto the ACME/DNS work. Reach it at
  # http://matts-server.tail01a272.ts.net:6976 (or http://100.118.206.104:6976).
  port = 6976;
  stateDir = "/var/lib/firefly-pico";
  tailnetIP = "100.118.206.104";

  # The AI assistant speaks the OpenAI wire format, so it can be pointed at services
  # already running on this box instead of a paid API:
  #   Ollama              -> 11434, OpenAI-compatible /v1 endpoint
  #   faster-whisper      -> 47770, OpenAI-compatible /v1/audio/transcriptions
  ollamaEndpoint = "http://${tailnetIP}:11434/v1/chat/completions";
  whisperEndpoint = "http://${tailnetIP}:47770/v1/audio/transcriptions";
in {
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 root root -"
    "d ${stateDir}/data 0750 root root -"
  ];

  virtualisation.oci-containers.containers."firefly-pico" = {
    image = "cioraneanu/firefly-pico:latest";
    autoStart = true;
    # Bind to the tailnet address only -- never 0.0.0.0.
    ports = ["${tailnetIP}:${toString port}:80"];
    volumes = ["${stateDir}/data:/var/www/html/database/data"];
    environment = {
      # Internal hop: plain HTTP, so Pico does not depend on certificate health.
      FIREFLY_URL = "http://firefly.matthandzel.com";

      ASSISTANT_LLM_ENDPOINT = ollamaEndpoint;
      ASSISTANT_LLM_MODEL = "llama3.1";
      # Ollama ignores the key but the client insists on a non-empty value.
      ASSISTANT_LLM_API_KEY = "ollama";
      ASSISTANT_LLM_CONTEXT = "";

      ASSISTANT_TRANSCRIPTION_ENDPOINT = whisperEndpoint;
      ASSISTANT_TRANSCRIPTION_MODEL = "Systran/faster-distil-whisper-large-v3";
      ASSISTANT_TRANSCRIPTION_API_KEY = "local";
      ASSISTANT_TRANSCRIPTION_LANGUAGE = "en";
    };
  };
}
