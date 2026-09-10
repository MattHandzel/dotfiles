#!/usr/bin/env zsh

# macOS: same three-entry menu (choose via the fuzzel shim); System Events
# does the shutdown/restart so open apps get their save dialogs.
if [[ "$(uname)" == Darwin ]]; then
  respond="$(printf '%s\n' " Shutdown" " Restart" " Cancel" | fuzzel --dmenu --lines=3 --width=10 --prompt='')"
  case "$respond" in
    " Shutdown") osascript -e 'tell application "System Events" to shut down' ;;
    " Restart") osascript -e 'tell application "System Events" to restart' ;;
    *) notify-send "cancel shutdown" ;;
  esac
  exit 0
fi

respond="$(echo " Shutdown\n Restart\n Cancel" | fuzzel --dmenu --lines=3 --width=10 --prompt='')"

if [ $respond = ' Shutdown' ] 
then
    echo "shutdown"
	shutdown now    
elif [ $respond = ' Restart' ] 
then
    echo "restart"
    reboot
else
    notify-send "cancel shutdown"
fi
