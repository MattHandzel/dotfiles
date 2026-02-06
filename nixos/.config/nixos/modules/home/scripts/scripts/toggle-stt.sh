#!/usr/bin/env bash
set -euo pipefail

# Check to see if user passed in --type or --copy

for arg in "$@"; do
  case $arg in
    --type)
      export STT_ACTION="type"
      shift
      ;;
    --copy)
      export STT_ACTION="copy"
      shift
      ;;
    *)
      echo "Usage: $0 [--type|--copy]"
      exit 1
      ;;
  esac
done

_UID="$(id -u)"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${_UID}/bus"
export XDG_RUNTIME_DIR="/run/user/${_UID}"
export PATH="/run/current-system/sw/bin:${HOME}/.nix-profile/bin:${PATH}"

PIDFILE="${XDG_RUNTIME_DIR}/stt-rec.pid"
# SCRIPT="/home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/stt_record.py"
SERVER="http://97.223.175.122:47770"

OUTFILE="/tmp/stt-output.txt"
LOGFILE="/tmp/stt.log"

BACKEND="pulse"
DEVICE="alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Mic1__source"
RATE=16000
CHANNELS=1

# whisper tuning for quality
ARGS=(
  --server "$SERVER"
  --pidfile "$PIDFILE"
  --backend "$BACKEND"
  --device "$DEVICE"
  --rate "$RATE"
  --channels "$CHANNELS"
  --stream
  --vad-level 2
  --frame-ms 20
  --silence-ms 1000
  --pre-roll-ms 350
  --max-utterance-ms 30000
  --min-seconds 1.0
  --context-chars 800
  --chunk-sep " "
  --prompt "This is a transcript of a thoughtful, continuous conversation. I will speak naturally; please punctuate correctly, avoiding fragmentation."
  --whisper-arg beam_size=5
  --whisper-arg best_of=5
  --whisper-arg temperature=0.2
  --whisper-arg condition_on_previous_text=true
  --whisper-arg vad_filter=true
  --whisper-arg no_speech_threshold=0.85
  --whisper-arg compression_ratio_threshold=2.3
  --whisper-arg logprob_threshold=-0.2
)

notify() {
  notify-send -u "${2:-low}" -t 1200 "🎙 STT" "$1" >/dev/null 2>&1 || true
}

cleanup_output() {
  # Fixes "word. lowercase" -> "word lowercase" (merges split sentences)
  sed -i -z -E 's/\. +([a-z])/ \1/g' "$OUTFILE"
  # Fixes "word ." -> "word." (removes space before punctuation)
  sed -i -E 's/ +([.,?!])/\1/g' "$OUTFILE"
  # Reduces excessive ellipses "..." to "." if desired, or just standardizes spacing
  # sed -i -E 's/\.\.\././g' "$OUTFILE"
}

copy_clipboard() {
  cleanup_output
  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy < "$OUTFILE" || true
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard < "$OUTFILE" || true
  fi
}

paste_text_with_wtype() {
  copy_clipboard
  if command -v wtype >/dev/null 2>&1; then
      wtype -M shift -M ctrl "v" 
      sleep 0.05
      wtype -m shift -m ctrl
    # cat "$OUTFILE"  | wtype -
  fi
}

write_text_with_wtype() {
  if command -v wtype >/dev/null 2>&1; then
    cat "$OUTFILE"  | wtype -
  fi
}

# ------------------------------------------------------------------------------

toggle_off() {
  local pid
  pid="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PIDFILE"
    notify "ℹ️ Nothing to stop" low
    exit 0
  fi

  notify "🟥 Stopping transcription…" normal
  echo "[toggle] $(date '+%H:%M:%S') Stopping PID $pid" >>"$LOGFILE"
  kill -INT "$pid" 2>/dev/null || true

  # Wait up to 35 seconds for clean exit (curl has 30s timeout)
  for _ in {1..175}; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done

  if kill -0 "$pid" 2>/dev/null; then
    echo "[toggle] $(date '+%H:%M:%S') PID $pid stuck, sending SIGKILL" >>"$LOGFILE"
    kill -KILL "$pid" 2>/dev/null || true
  fi

  rm -f "$PIDFILE" || true

  if [[ -s "$OUTFILE" ]]; then
    if [[ "$STT_ACTION" == "copy" ]]; then
      copy_clipboard
      notify "✅ Transcript copied to clipboard" normal
    fi
    if [[ "$STT_ACTION" == "type" ]]; then
       paste_text_with_wtype 
      notify "✅ Transcript typed out" normal
    fi

  else
    notify "⚠️ No transcript captured. Check /tmp/stt.log for details." normal
    echo "[toggle] $(date '+%H:%M:%S') No transcript captured in $OUTFILE" >>"$LOGFILE"
  fi
}

toggle_on() {
  echo "[toggle] $(date '+%H:%M:%S') Starting STT..." >>"$LOGFILE"
  echo "[toggle] Server: $SERVER" >>"$LOGFILE"
  : >"$OUTFILE"

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOCAL_SCRIPT="${SCRIPT_DIR}/stt_record.py"

  if [[ -f "$LOCAL_SCRIPT" ]]; then
      echo "[toggle] Using local script: $LOCAL_SCRIPT" >>"$LOGFILE"
      # Use the shebang of the local script
      nohup "$LOCAL_SCRIPT" "${ARGS[@]}" >"$OUTFILE" 2>>"$LOGFILE" &
  elif command -v stt-record >/dev/null 2>&1; then
      echo "[toggle] Using binary: stt-record ${ARGS[*]}" >>"$LOGFILE"
      nohup stt-record "${ARGS[@]}" >"$OUTFILE" 2>>"$LOGFILE" &
  else
      # Fallback to nix-shell if neither is found (though local should be there)
      SCRIPT="/home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/stt_record.py"
      echo "[toggle] Using nix-shell with: $SCRIPT" >>"$LOGFILE"
      nohup nix-shell -p python311 python311Packages.webrtcvad python311Packages.setuptools --run "$SCRIPT ${ARGS[*]}" >"$OUTFILE" 2>>"$LOGFILE" & 
  fi
  disown
  # wait up to 2 s for PIDFILE to appear
  for _ in {1..20}; do
    [[ -f "$PIDFILE" ]] && break
    sleep 0.1
  done

  if [[ -f "$PIDFILE" ]]; then
    echo "[toggle] PIDFILE=$(cat "$PIDFILE")" >>"$LOGFILE"
    notify "🎙 Recording started" low
  else
    notify "⚠️ Failed to start (no PIDFILE written)" critical
    echo "[toggle] Failed: no PIDFILE" >>"$LOGFILE"
  fi
}

# ------------------------------------------------------------------------------

if [[ -f "$PIDFILE" ]]; then
  PID="$(cat "$PIDFILE" 2>/dev/null || true)"
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    toggle_off
  else
    rm -f "$PIDFILE"
    toggle_on
  fi
else
  toggle_on
fi


# /home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/stt_record.py --server http://97.223.175.122:47770 --pidfile /run/user/1000/stt-rec.pid --backend pulse --device alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Mic1__source --rate 16000 --channels 1 --stream --vad-level 3 --frame-ms 20 --silence-ms 900 --pre-roll-ms 350 --max-utterance-ms 30000 --min-seconds 1.0 --context-chars 800 --chunk-sep " " --whisper-arg beam_size=8 --whisper-arg best_of=8 --whisper-arg temperature=0.2 --whisper-arg condition_on_previous_text=true --whisper-arg vad_filter=true --whisper-arg no_speech_threshold=0.85 --whisper-arg compression_ratio_threshold=2.3 --whisper-arg logprob_threshold=-0.2

# nix-shell -p gcc cmake 'python311.withPackages (ps: [ps.webrtcvad ps.setuptools])' --run "/home/matth/dotfiles/nixos/.config/nixos/modules/home/scripts/scripts/stt_record.py --server http://97.223.175.122:47770 --pidfile /run/user/1000/stt-rec.pid --backend pulse --device alsa_input.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__Mic1__source --rate 16000 --channels 1 --stream --vad-level 3 --frame-ms 20 --silence-ms 900 --pre-roll-ms 350 --max-utterance-ms 30000 --min-seconds 1.0 --context-chars 800 --chunk-sep \" \" --whisper-arg beam_size=8 --whisper-arg best_of=8 --whisper-arg temperature=0.2 --whisper-arg condition_on_previous_text=true --whisper-arg vad_filter=true --whisper-arg no_speech_threshold=0.85 --whisper-arg compression_ratio_threshold=2.3 --whisper-arg logprob_threshold=-0.2"
