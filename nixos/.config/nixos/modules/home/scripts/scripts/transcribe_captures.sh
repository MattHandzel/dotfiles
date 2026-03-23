#!/usr/bin/env bash

# transcribe_captures.sh
# This script processes audio recordings for the Knowledge Operating System.

# Define source and target directories
SOURCE_DIRS=(
    "$HOME/notes/capture/raw_capture/audio_recordings"
    "$HOME/Obsidian/Main/capture/raw_capture/media"
    "$HOME/Obsidian/Main/archive/capture/raw_capture"
)
TARGET_DIR="$HOME/notes/capture/raw_capture/audio_recordings_transcripts"
TRANSCRIBE_TOOL="/home/matth/Projects/KnowledgeOperatingSystem/MeetingTranscribe"

mkdir -p "$TARGET_DIR"

echo "[transcribe] Starting capture processing..."

process_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        return
    fi

    # 1. Handle zip files
    shopt -s nullglob
    local zip_files=("$dir"/*.zip)
    if [ ${#zip_files[@]} -gt 0 ]; then
        echo "[transcribe] Processing zips in $dir..."
        for zip_file in "${zip_files[@]}"; do
            echo "[transcribe] Unzipping $(basename "$zip_file")..."
            unzip -o "$zip_file" -d "$dir"
            mkdir -p "$dir/processed"
            mv "$zip_file" "$dir/processed/"
        done
    fi

    # 2. Transcribe audio files
    local audio_files=("$dir"/*.wav "$dir"/*.mp3 "$dir"/*.m4a "$dir"/*.ogg "$dir"/*.flac)

    if [ ${#audio_files[@]} -eq 0 ]; then
        return
    fi

    echo "[transcribe] Processing directory: $dir"

    for audio_file in "${audio_files[@]}"; do
        filename=$(basename "$audio_file")
        basename="${filename%.*}"
        transcript_file="$TARGET_DIR/${basename}.txt"
        
        # Skip if already transcribed
        if [ -f "$transcript_file" ]; then
            echo "[transcribe] Skipping $filename (already transcribed, moving to processed)."
            mkdir -p "$dir/processed"
            mv "$audio_file" "$dir/processed/"
            continue
        fi
        
        echo "[transcribe] Processing $filename..."
        
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
            mkdir -p "$dir/processed"
            mv "$audio_file" "$dir/processed/"
        else
            echo "[transcribe] Failed to transcribe $filename"
        fi
    done
}

for dir in "${SOURCE_DIRS[@]}"; do
    process_dir "$dir"
done

echo "[transcribe] Processing complete."
