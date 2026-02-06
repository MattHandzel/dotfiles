#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ===
OLLAMA_HOST="http://97.223.175.122:11434"   # remote Ollama server
MODEL="mistral:7b"

VERBOSE=0
if [[ "${1:-}" == "-v" ]]; then
  VERBOSE=1
  shift
fi

log() {
  if [[ $VERBOSE -eq 1 ]]; then
    echo "[llm_clip] $*" >&2
  fi
}

# === 0) Health check Ollama ===
if ! curl -s --connect-timeout 3 "$OLLAMA_HOST/api/tags" > /dev/null; then
  notify-send -t 3000 -u critical -i dialog-error "❌ Ollama server not reachable" "Endpoint: $OLLAMA_HOST"
  exit 1
fi
log "✅ Ollama server reachable at $OLLAMA_HOST"

# === 1) Get clipboard ===
INPUT="$(wl-paste)"
log "📋 Captured clipboard (${#INPUT} chars)"

# === 2) Choose task with fuzzel (with emojis) ===
KEY=$(printf "🎙️ voice_memo_cleanup\n📑 markdown_formatter\n📝 summarize\n🔍 ocr_cleanup\n🌎 translate\n" | fuzzel --dmenu)
[ -z "${KEY:-}" ] && exit 0
log "🔧 Selected task: $KEY"

# === 3) Per-task variables ===
VARS=()
case "$KEY" in
  "🌎 translate")
    LANG_CHOICE=$(printf "Spanish\nPolish\nFrench\nGerman" | fuzzel --dmenu)
    [ -n "$LANG_CHOICE" ] && VARS+=(language="$LANG_CHOICE")
    ;;
  "🎭 rewrite_tone")
    STYLE_CHOICE=$(printf "formal\ncasual\nplayful\nprofessional" | fuzzel --dmenu)
    [ -n "$STYLE_CHOICE" ] && VARS+=(style="$STYLE_CHOICE")
    ;;
  *)
    :
    ;;
esac
log "📦 Vars: ${VARS[*]:-(none)}"

# === 4) Build prompt with Python ===
PROMPT="$(printf "%s" "$INPUT" | python3 /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/prompt-llm.py "$KEY" "${VARS[@]}")"

# === 5) Notify start ===
notify-send -t 2000 -u normal -i dialog-information "Processing ($KEY)…"
log "🚀 Sending request to Ollama"

# === 6) Call Ollama ===
REQ_JSON="$(jq -n --arg m "$MODEL" --arg p "$PROMPT" '{model:$m, prompt:$p, stream:false}')"
RESP="$(curl -s -X POST "$OLLAMA_HOST/api/generate" -H "Content-Type: application/json" -d "$REQ_JSON")"
OUTPUT="$(printf "%s" "$RESP" | jq -r '.response')"

# === 7) Clipboard + notify ===
printf "%s" "$OUTPUT" | wl-copy
notify-send -t 2000 -u critical -i dialog-information "✅ Done" "Output copied"
log "✅ Output length: ${#OUTPUT} chars"
