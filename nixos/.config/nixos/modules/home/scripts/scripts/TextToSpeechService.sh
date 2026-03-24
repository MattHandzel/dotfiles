#!/usr/bin/env bash

set -euo pipefail

SERVICE_URL="${TEXT_TO_SPEECH_SERVICE_URL:-http://100.118.206.104:47773}"
VOICE="${TEXT_TO_SPEECH_SERVICE_VOICE:-en_US-lessac-high}"
SPEED="${TEXT_TO_SPEECH_SERVICE_SPEED:-0.95}"
FORMAT="mp3"
INPUT_FORMAT="text"
OUTPUT_PATH=""
PLAY_AUDIO=1
STREAM_AUDIO=0
STREAM_PLAYED=0
REFRESH_CACHE=0
CACHE_DIR="${TEXT_TO_SPEECH_SERVICE_CACHE_DIR:-$HOME/.cache/text-to-speech-service/client}"
CONNECT_TIMEOUT="${TEXT_TO_SPEECH_SERVICE_CONNECT_TIMEOUT:-5}"
MAX_TIME="${TEXT_TO_SPEECH_SERVICE_MAX_TIME:-900}"
RETRIES="${TEXT_TO_SPEECH_SERVICE_RETRIES:-4}"

usage() {
  cat <<'EOF'
Usage:
  TextToSpeechService [options] "text to speak"
  echo "text to speak" | TextToSpeechService [options]

Options:
  --voice VOICE           Voice id to request
  --speed SPEED           Speed between 0.7 and 1.4
  --format FORMAT         mp3 or wav
  --input-format FORMAT   text or markdown
  --save PATH             Save audio to PATH
  --out PATH              Alias for --save
  --stream                Use streaming endpoint (mp3 only)
  --refresh               Ignore local wrapper cache and force a new request
  --no-play               Do not play after generation
  --url URL               Override service base URL
  --help                  Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --voice)
      VOICE="$2"
      shift 2
      ;;
    --speed)
      SPEED="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --input-format)
      INPUT_FORMAT="$2"
      shift 2
      ;;
    --save)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --out)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --stream)
      STREAM_AUDIO=1
      shift
      ;;
    --refresh)
      REFRESH_CACHE=1
      shift
      ;;
    --no-play)
      PLAY_AUDIO=0
      shift
      ;;
    --url)
      SERVICE_URL="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  TEXT="$*"
else
  TEXT="$(cat)"
fi

if [[ -z "${TEXT// }" ]]; then
  echo "No input text provided." >&2
  exit 1
fi

if [[ "$STREAM_AUDIO" -eq 1 && "$FORMAT" != "mp3" ]]; then
  echo "--stream currently supports only mp3 output." >&2
  exit 1
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  BASENAME="$(printf '%s' "$TEXT" \
    | tr '\n' ' ' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/ /g' \
    | awk '{for (i = 1; i <= NF && i <= 8; ++i) printf "%s%s", (i == 1 ? "" : "-"), $i}')"
  if [[ -z "$BASENAME" ]]; then
    BASENAME="speech"
  fi
  OUTPUT_PATH="/tmp/${BASENAME}-$(date +%Y%m%d-%H%M%S).$FORMAT"
fi

mkdir -p "$CACHE_DIR"
mkdir -p "$(dirname "$OUTPUT_PATH")"

PAYLOAD="$(jq -n \
  --arg text "$TEXT" \
  --arg input_format "$INPUT_FORMAT" \
  --arg voice "$VOICE" \
  --arg format "$FORMAT" \
  --argjson speed "$SPEED" \
  '{text: $text, input_format: $input_format, voice: $voice, format: $format, speed: $speed}')"

ENDPOINT="/speak"
if [[ "$STREAM_AUDIO" -eq 1 ]]; then
  ENDPOINT="/stream"
fi

REQUEST_KEY="$(printf '%s' "$ENDPOINT$PAYLOAD" | sha256sum | awk '{print $1}')"
CACHE_PATH="$CACHE_DIR/$REQUEST_KEY.$FORMAT"
TEMP_PATH="$(mktemp "$CACHE_DIR/.download-XXXXXX.$FORMAT")"

fetch_audio() {
  curl --fail --silent --show-error \
    --retry "$RETRIES" \
    --retry-all-errors \
    --retry-delay 1 \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    "$SERVICE_URL$ENDPOINT" \
    -H 'content-type: application/json' \
    -d "$PAYLOAD" \
    > "$TEMP_PATH"
}

fetch_audio_and_play() {
  curl --fail --silent --show-error \
    --retry "$RETRIES" \
    --retry-all-errors \
    --retry-delay 1 \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    "$SERVICE_URL$ENDPOINT" \
    -H 'content-type: application/json' \
    -d "$PAYLOAD" \
    | tee "$TEMP_PATH" \
    | mpv --no-terminal --no-video -
}

if [[ "$REFRESH_CACHE" -eq 0 && -f "$CACHE_PATH" ]]; then
  cp "$CACHE_PATH" "$OUTPUT_PATH"
else
  if [[ "$STREAM_AUDIO" -eq 1 && "$PLAY_AUDIO" -eq 1 ]]; then
    if fetch_audio_and_play; then
      STREAM_PLAYED=1
      mv "$TEMP_PATH" "$OUTPUT_PATH"
      cp "$OUTPUT_PATH" "$CACHE_PATH"
    else
      rm -f "$TEMP_PATH"
      if [[ -f "$CACHE_PATH" ]]; then
        echo "Network request failed, using cached audio: $CACHE_PATH" >&2
        cp "$CACHE_PATH" "$OUTPUT_PATH"
      else
        echo "Streaming request failed and no cached audio exists." >&2
        exit 1
      fi
    fi
  else
    if fetch_audio; then
      mv "$TEMP_PATH" "$OUTPUT_PATH"
      cp "$OUTPUT_PATH" "$CACHE_PATH"
    else
      rm -f "$TEMP_PATH"
      if [[ -f "$CACHE_PATH" ]]; then
        echo "Network request failed, using cached audio: $CACHE_PATH" >&2
        cp "$CACHE_PATH" "$OUTPUT_PATH"
      else
        echo "Network request failed and no cached audio exists." >&2
        exit 1
      fi
    fi
  fi
fi

if [[ "$PLAY_AUDIO" -eq 1 && "$STREAM_PLAYED" -eq 0 ]]; then
  mpv --no-video "$OUTPUT_PATH"
fi

echo "$OUTPUT_PATH"
