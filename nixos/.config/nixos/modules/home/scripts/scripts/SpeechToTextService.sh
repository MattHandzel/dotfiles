#!/usr/bin/env bash

set -euo pipefail

SERVICE_URL="${SPEECH_TO_TEXT_SERVICE_URL:-http://100.118.206.104:47773}"
VOICE="${SPEECH_TO_TEXT_SERVICE_VOICE:-narrator}"
SPEED="${SPEECH_TO_TEXT_SERVICE_SPEED:-1.0}"
FORMAT="mp3"
INPUT_FORMAT="text"
OUTPUT_PATH=""
PLAY_AUDIO=1
STREAM_AUDIO=0

usage() {
  cat <<'EOF'
Usage:
  SpeechToTextService [options] "text to speak"
  echo "text to speak" | SpeechToTextService [options]

Options:
  --voice VOICE           Voice id to request
  --speed SPEED           Speed between 0.7 and 1.4
  --format FORMAT         mp3 or wav
  --input-format FORMAT   text or markdown
  --save PATH             Save audio to PATH
  --stream                Use streaming endpoint (mp3 only)
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
    --stream)
      STREAM_AUDIO=1
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
  OUTPUT_PATH="/tmp/speech-to-text-service-$(date +%Y%m%d-%H%M%S).$FORMAT"
fi

PAYLOAD="$(jq -n \
  --arg text "$TEXT" \
  --arg input_format "$INPUT_FORMAT" \
  --arg voice "$VOICE" \
  --arg format "$FORMAT" \
  --argjson speed "$SPEED" \
  '{text: $text, input_format: $input_format, voice: $voice, format: $format, speed: $speed}')"

if [[ "$STREAM_AUDIO" -eq 1 ]]; then
  if [[ "$PLAY_AUDIO" -eq 1 ]]; then
    curl --fail --silent --show-error \
      "$SERVICE_URL/stream" \
      -H 'content-type: application/json' \
      -d "$PAYLOAD" \
      | tee "$OUTPUT_PATH" \
      | mpv --no-video -
  else
    curl --fail --silent --show-error \
      "$SERVICE_URL/stream" \
      -H 'content-type: application/json' \
      -d "$PAYLOAD" \
      > "$OUTPUT_PATH"
  fi
else
  curl --fail --silent --show-error \
    "$SERVICE_URL/speak" \
    -H 'content-type: application/json' \
    -d "$PAYLOAD" \
    > "$OUTPUT_PATH"

  if [[ "$PLAY_AUDIO" -eq 1 ]]; then
    mpv --no-video "$OUTPUT_PATH"
  fi
fi

echo "$OUTPUT_PATH"
