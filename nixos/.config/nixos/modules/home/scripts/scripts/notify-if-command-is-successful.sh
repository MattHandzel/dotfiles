#!/usr/bin/env bash 

# Check if the command was successful
if [ $? -eq 0 ]; then
    notify-send -t 2000 -u normal -i dialog-information "🎉 Success!" "The command '$@' completed successfully."
else
    notify-send -t 2000 -u critical -i dialog-error "😞 Failure" "The command '$@' encountered an error."
fi
