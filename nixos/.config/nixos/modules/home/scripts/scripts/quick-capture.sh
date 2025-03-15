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

# Function to capture clipboard content
capture_clipboard() {
    wl-paste > "${NOTES_DIR}/${CURRENT_TIME}_clipboard.txt"
}

# Function to capture video (uses wf-recorder for Wayland)
capture_video() {
    wf-recorder -f "${NOTES_DIR}/${CURRENT_TIME}.mp4" &
    PID=$!
    zenity --info --text="Recording video. Press OK to stop." --title="Video Recording"
    kill $PID
}

# Function to capture audio (uses arecord)
capture_audio() {
    arecord -f cd "${NOTES_DIR}/${CURRENT_TIME}.wav" &
    PID=$!
    zenity --info --text="Recording audio. Press OK to stop." --title="Audio Recording"
    kill $PID
}

# Function to capture picture (uses grim)
capture_picture() {
    grim "${NOTES_DIR}/${CURRENT_TIME}.png"
}

# Function to capture the most recent screenshot
capture_screenshot() {
    latest_screenshot=$(ls -t ~/Pictures/*.png | head -n 1)
    cp "$latest_screenshot" "${NOTES_DIR}/${CURRENT_TIME}_screenshot.png"
}

# Function to handle file attachments
capture_files() {
    for filepath in "$@"; do
        cp "$filepath" "${NOTES_DIR}/$(basename "$filepath" | sed "s/^\(.*\)\.\(.*\)$/\1_${CURRENT_TIME}.\2/")"
    done
}

# Step 1: Select modalities using Zenity checklist
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

IFS=":" read -r -a OPTIONS <<< "$SELECTION"

# Step 2: Capture text if selected
if [[ " ${OPTIONS[*]} " =~ " Text " ]]; then
    NOTE_TEXT=$(zenity --entry --title="Quick Capture" --text="Enter your note:")
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
            FILES=$(zenity --file-selection --multiple --title="Select Files")
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
