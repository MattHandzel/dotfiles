#!/usr/bin/env bash
set -euo pipefail

NTFY_URL="${NTFY_URL:-http://server.matthandzel.com:8124}"
TOPIC="claude"
TITLE=""
PRIORITY="default"
TAGS=""
DELAY=""
CLICK=""
MESSAGE=""

usage() {
    cat <<EOF
Usage: send-to-phone-ntfy [options] [MESSAGE]

Send a push notification to Matt's phone via ntfy.
If MESSAGE is omitted, reads from stdin.

Options:
  -t, --title TITLE       Notification title
  -p, --priority PRIO     min | low | default | high | urgent (default: default)
  -T, --tags TAGS         Comma-separated tags (emoji shortcodes), e.g. "warning,robot"
      --topic TOPIC       ntfy topic (default: claude)
      --delay WHEN        Schedule for later, e.g. "30min", "tomorrow, 9am", ISO timestamp
      --click URL         URL to open when tapped
      --url URL           Override ntfy server URL (default: \$NTFY_URL or server.matthandzel.com:8124)
  -h, --help              Show this help

Examples:
  send-to-phone-ntfy "build finished"
  send-to-phone-ntfy -t "Reminder" -p high "stand up and stretch"
  echo "$(date)" | send-to-phone-ntfy -t "Heartbeat"
  send-to-phone-ntfy --delay "30min" "drink water"
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--title) TITLE="$2"; shift 2 ;;
        -p|--priority) PRIORITY="$2"; shift 2 ;;
        -T|--tags) TAGS="$2"; shift 2 ;;
        --topic) TOPIC="$2"; shift 2 ;;
        --delay) DELAY="$2"; shift 2 ;;
        --click) CLICK="$2"; shift 2 ;;
        --url) NTFY_URL="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; MESSAGE="${MESSAGE:+$MESSAGE }$*"; break ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) MESSAGE="${MESSAGE:+$MESSAGE }$1"; shift ;;
    esac
done

if [[ -z "$MESSAGE" ]]; then
    if [[ -t 0 ]]; then
        echo "Error: no message provided (pass as arg or pipe via stdin)" >&2
        usage >&2
        exit 2
    fi
    MESSAGE="$(cat)"
fi

if [[ -z "$MESSAGE" ]]; then
    echo "Error: empty message" >&2
    exit 2
fi

args=(-fsS -X POST -H "Priority: $PRIORITY")
[[ -n "$TITLE" ]] && args+=(-H "Title: $TITLE")
[[ -n "$TAGS"  ]] && args+=(-H "Tags: $TAGS")
[[ -n "$DELAY" ]] && args+=(-H "Delay: $DELAY")
[[ -n "$CLICK" ]] && args+=(-H "Click: $CLICK")
args+=(--data-binary "$MESSAGE" "$NTFY_URL/$TOPIC")

curl "${args[@]}" >/dev/null
echo "Sent to $NTFY_URL/$TOPIC"
