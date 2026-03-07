#!/usr/bin/env bash

# transcribe_captures.sh
# This script processes audio recordings for the Knowledge Operating System.

SOURCE_DIR="$HOME/notes/capture/raw_capture/audio_recordings"
TARGET_DIR="$HOME/notes/capture/raw_capture/audio_recordings_transcripts"
TRANSCRIBE_TOOL="/home/matth/Projects/KnowledgeOperatingSystem/MeetingTranscribe"

mkdir -p "$TARGET_DIR"

echo "[transcribe] Starting capture processing..."

# 1. Handle zip files
for zip_file in "$SOURCE_DIR"/*.zip; do
    if [ -e "$zip_file" ]; then
        echo "[transcribe] Unzipping $(basename "$zip_file")..."
        unzip -o "$zip_file" -d "$SOURCE_DIR"
        # We NO LONGER delete any audio files (including zips) as per user request.
        # rm "$zip_file"
    fi
done

# 2. Transcribe audio files
# We look for common audio extensions
shopt -s nullglob
audio_files=("$SOURCE_DIR"/*.wav "$SOURCE_DIR"/*.mp3 "$SOURCE_DIR"/*.m4a "$SOURCE_DIR"/*.ogg "$SOURCE_DIR"/*.flac)

if [ ${#audio_files[@]} -eq 0 ]; then
    echo "[transcribe] No audio files found in $SOURCE_DIR."
    exit 0
fi

for audio_file in "${audio_files[@]}"; do
    filename=$(basename "$audio_file")
    
    # Skip the large files for the initial test if we are in "test mode"
    # (For this specific task, I'll just run it on the one the user wants)
    
    basename="${filename%.*}"
    transcript_file="$TARGET_DIR/${basename}.txt"
    
    # Skip if already transcribed (optional, but good for a pipeline)
    if [ -f "$transcript_file" ]; then
        echo "[transcribe] Skipping $filename (already transcribed, moving to processed)."
        mkdir -p "$SOURCE_DIR/processed"
        mv "$audio_file" "$SOURCE_DIR/processed/"
        continue
    fi
    
    echo "[transcribe] Processing $filename..."
    
    # TODO: Add multi-speaker detection (diarization) in the future.
    # Currently assuming single speaker for simplicity and performance.
    
    # Run the transcription tool via nix run
    nix run "$TRANSCRIBE_TOOL" -- \
        "$audio_file" \
        --transcript-path "$transcript_file" \
        --timestamps \
        --silence-ms 1000 \
        --no-noise-filter
        
    if [ $? -eq 0 ]; then
        echo "[transcribe] Successfully transcribed $filename to $(basename "$transcript_file")"
        # Move to processed folder to prevent re-processing
        mkdir -p "$SOURCE_DIR/processed"
        mv "$audio_file" "$SOURCE_DIR/processed/"
    else
        echo "[transcribe] Failed to transcribe $filename"
    fi
done

echo "[transcribe] Processing complete."
