#!/bin/bash

LOG_FILE="/tmp/system-sleep-lock.log"

echo "[$(date)] System sleep hook triggered: $1/$2" >> "$LOG_FILE"

if [ "$1" = pre ]; then
    echo "[$(date)] Locking screen as matthandzel" >> "$LOG_FILE"
    export DISPLAY=:1
    export XAUTHORITY=/home/matthandzel/.Xauthority
    su matthandzel -c '/usr/bin/xsecurelock' >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
      echo "[$(date)] xsecurelock failed to execute" >> "$LOG_FILE"
    fi
fi

if [ "$1" = post ]; then
    echo "[$(date)] System resumes from sleep" >> "$LOG_FILE"
fi

