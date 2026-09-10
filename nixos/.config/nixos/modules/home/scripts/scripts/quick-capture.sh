#!/bin/bash

# Define the notes directory
NOTES_DIR="$HOME/notes/capture/raw_capture"
mkdir -p "$NOTES_DIR"

# Get the current date in the format YYYY-MM-DD
TODAY=$(date +%Y-%m-%d)

# Get the current timestamp in the format YYYY-MM-DD HH:MM
TIMESTAMP=$(date +"%Y-%m-%d %H:%M.%3N %Z")

# Define the file for today's notes
TODAY_FILE="${NOTES_DIR}/${TODAY}.md"

DARWIN=0; [[ "$(uname)" == Darwin ]] && DARWIN=1

# macOS stand-ins: pbpaste, screencapture (-v records video until you click
# Stop in the menu bar), ffmpeg's avfoundation mic, osascript dialogs for
# zenity, and the system screenshot folder.
osa_info() { /usr/bin/osascript -e 'on run argv' -e 'display dialog (item 1 of argv) with title (item 2 of argv) buttons {"OK"} default button "OK"' -e 'end run' -- "$1" "$2" >/dev/null; }

# Function to capture clipboard content
capture_clipboard() {
    if (( DARWIN )); then pbpaste > "${NOTES_DIR}/${CURRENT_TIME}_clipboard.txt"; else
    wl-paste > "${NOTES_DIR}/${CURRENT_TIME}_clipboard.txt"; fi
}

# Function to capture video (uses wf-recorder for Wayland)
capture_video() {
    if (( DARWIN )); then
        /usr/sbin/screencapture -v "${NOTES_DIR}/${CURRENT_TIME}.mp4"
        return
    fi
    wf-recorder -f "${NOTES_DIR}/${CURRENT_TIME}.mp4" &
    PID=$!
    zenity --info --text="Recording video. Press OK to stop." --title="Video Recording"
    kill $PID
}

# Function to capture audio (uses arecord)
capture_audio() {
    if (( DARWIN )); then
        ffmpeg -hide_banner -loglevel error -f avfoundation -i ":0" -ac 2 -ar 44100 "${NOTES_DIR}/${CURRENT_TIME}.wav" &
        PID=$!
        osa_info "Recording audio. Press OK to stop." "Audio Recording"
        kill -INT $PID; wait $PID 2>/dev/null
        return
    fi
    arecord -f cd "${NOTES_DIR}/${CURRENT_TIME}.wav" &
    PID=$!
    zenity --info --text="Recording audio. Press OK to stop." --title="Audio Recording"
    kill $PID
}

# Function to capture picture (uses grim)
capture_picture() {
    if (( DARWIN )); then /usr/sbin/screencapture -x "${NOTES_DIR}/${CURRENT_TIME}.png"; else
    grim "${NOTES_DIR}/${CURRENT_TIME}.png"; fi
}

# Function to capture the most recent screenshot
capture_screenshot() {
    if (( DARWIN )); then
        shots="$(defaults read com.apple.screencapture location 2>/dev/null || echo "$HOME/Desktop")"
        latest_screenshot=$(ls -t "${shots/#\~/$HOME}"/*.png ~/Pictures/Screenshots/*.png 2>/dev/null | head -n 1)
    else
        latest_screenshot=$(ls -t ~/Pictures/*.png | head -n 1)
    fi
    cp "$latest_screenshot" "${NOTES_DIR}/${CURRENT_TIME}_screenshot.png"
}

# Function to handle file attachments
capture_files() {
    for filepath in "$@"; do
        cp "$filepath" "${NOTES_DIR}/$(basename "$filepath" | sed "s/^\(.*\)\.\(.*\)$/\1_${CURRENT_TIME}.\2/")"
    done
}

# Step 1: Select modalities using Zenity checklist (macOS: choose from list)
if (( DARWIN )); then
    SELECTION=$(/usr/bin/osascript -e 'set r to choose from list {"Text", "Clipboard", "Video", "Audio", "Picture", "Most Recent Screenshot", "File Attachments"} with title "Quick Capture" with prompt "Select modalities:" default items {"Text"} with multiple selections allowed' \
        -e 'if r is false then return ""' \
        -e 'set AppleScript'"'"'s text item delimiters to ":"' \
        -e 'return r as text' 2>/dev/null)
else
SELECTION=$(zenity --list --checklist --title="Quick Capture" \
    --text="Select modalities:" \
    --column="Pick" --column="Action" \
    TRUE "Text" \
    FALSE "Clipboard" \
    FALSE "Video" \
    FALSE "Audio" \
    FALSE "Picture" \
    FALSE "Most Recent Screenshot" \
    FALSE "File Attachments" \
    --separator=":")
fi
[[ -n "$SELECTION" ]] || exit 0

IFS=":" read -r -a OPTIONS <<< "$SELECTION"

# Step 2: Capture text if selected
if [[ " ${OPTIONS[*]} " =~ " Text " ]]; then
    if (( DARWIN )); then
        NOTE_TEXT=$(/usr/bin/osascript -e 'text returned of (display dialog "Enter your note:" with title "Quick Capture" default answer "")' 2>/dev/null)
    else
    NOTE_TEXT=$(zenity --entry --title="Quick Capture" --text="Enter your note:")
    fi
fi

# Step 3: Capture selected modalities
CURRENT_TIME=$(date +"%Y-%m-%d_%H-%M-%S.%3N %Z")
for opt in "${OPTIONS[@]}"; do
    case $opt in
        "Clipboard") capture_clipboard ;;
        "Video") capture_video ;;
        "Audio") capture_audio ;;
        "Picture") capture_picture ;;
        "Most Recent Screenshot") capture_screenshot ;;
        "File Attachments")
            if (( DARWIN )); then
                FILES=$(/usr/bin/osascript -e 'set fs to choose file with prompt "Select Files" with multiple selections allowed' \
                    -e 'set out to {}' -e 'repeat with f in fs' -e 'set end of out to POSIX path of f' -e 'end repeat' \
                    -e 'set AppleScript'"'"'s text item delimiters to "|"' -e 'return out as text' 2>/dev/null)
            else
            FILES=$(zenity --file-selection --multiple --title="Select Files")
            fi
            IFS="|" read -r -a FILE_ARRAY <<< "$FILES"
            capture_files "${FILE_ARRAY[@]}"
            ;;
    esac
done

# Step 4: Append to the markdown note
{
    echo -e "\n$CURRENT_TIME"
    [[ " ${OPTIONS[*]} " =~ " Text " ]] && echo "Text: \"$NOTE_TEXT\""
    [[ " ${OPTIONS[*]} " =~ " Clipboard " ]] && echo "Clipboard: $(< "${NOTES_DIR}/${CURRENT_TIME}_clipboard.txt")"
    [[ " ${OPTIONS[*]} " =~ " Video " ]] && echo "Video: [Video](./${CURRENT_TIME}.mp4)"
    [[ " ${OPTIONS[*]} " =~ " Audio " ]] && echo "Audio: [Audio](./${CURRENT_TIME}.wav)"
    [[ " ${OPTIONS[*]} " =~ " Picture " ]] && echo "Picture: ![Image](./${CURRENT_TIME}.png)"
    [[ " ${OPTIONS[*]} " =~ " Most Recent Screenshot " ]] && echo "Screenshot: ![Screenshot](./${CURRENT_TIME}_screenshot.png)"
    if [[ " ${OPTIONS[*]} " =~ " File Attachments " ]]; then
        echo "Files:"
        for f in "${NOTES_DIR}"/*"${CURRENT_TIME}"*; do
            echo "  - [File Attachment](./$(basename "$f"))"
        done
    fi
} >> "$TODAY_FILE"

# Step 5: Completion message
notify-send -t 2000 -u normal -i dialog-information "Success ✅!" ""
