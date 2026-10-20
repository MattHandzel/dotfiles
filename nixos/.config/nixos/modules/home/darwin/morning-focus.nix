# Morning focus: the first time the laptop is used each morning, quit the
# messaging apps and open today's daily note.
#
# WHY (2026-10-01, CFAR TAPs class): Matt's TAP trigger is "I open my laptop".
# The action he wanted was to kill every distraction and start on the daily
# note's top task, not on Slack. This makes the first half of that action
# automatic, so the only thing left to do is the task itself.
#
# HOW IT FIRES: a launchd agent ticks every 60 s. launchd interval timers do not
# fire while the Mac sleeps, so the first tick after the lid opens is, in
# practice, "the laptop was just opened". The script runs its action at most
# once per day, only between 05:00 and 11:59, only while the screen is unlocked,
# and only when the keyboard or mouse was touched in the last 2 minutes. That
# last check stops a Power Nap dark wake from firing it with nobody there.
#
# Manual run (ignores the window and the once-a-day stamp): `morning-focus --force`
# Log: ~/Library/Logs/morning-focus.log
{pkgs, ...}: let
  apps = [
    "Slack"
    "Beeper Desktop"
    "Superhuman"
    "Mail"
    "Messages"
    "Discord"
    "WhatsApp"
  ];

  morningFocus = pkgs.writeShellApplication {
    name = "morning-focus";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      PATH="$PATH:/usr/bin:/bin:/usr/sbin"
      state_dir="$HOME/.local/state/morning-focus"
      stamp="$state_dir/last-run"
      today="$(date +%F)"
      force=0
      [ "''${1:-}" = "--force" ] && force=1

      if [ "$force" -eq 0 ]; then
        hour="$(date +%H)"
        [ "$hour" -ge 5 ] && [ "$hour" -lt 12 ] || exit 0
        [ "$(cat "$stamp" 2>/dev/null || true)" = "$today" ] && exit 0
        # Locked screen: CGSSessionScreenIsLocked only appears while locked.
        if ioreg -n Root -d1 -a | grep -q CGSSessionScreenIsLocked; then exit 0; fi
        idle="$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')"
        [ "''${idle:-9999}" -lt 120 ] || exit 0
      fi

      mkdir -p "$state_dir"
      echo "$today" > "$stamp"

      closed=()
      for app in ${pkgs.lib.escapeShellArgs apps}; do
        if [ "$(osascript -e "application \"$app\" is running" 2>/dev/null)" = "true" ]; then
          osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || true
          closed+=("$app")
        fi
      done

      note="$HOME/Obsidian/Main/dailies/$today.md"
      if [ -f "$note" ]; then
        open "obsidian://open?vault=Main&file=dailies%2F$today"
      else
        open -a Obsidian
      fi

      echo "$(date -u +%FT%TZ) closed: ''${closed[*]:-none}; opened daily note"
      osascript -e 'display notification "Messaging apps closed. Start the daily note top task." with title "Morning focus"' || true
    '';
  };
in {
  home.packages = [morningFocus];

  launchd.agents.morning-focus = {
    enable = true;
    config = {
      ProgramArguments = ["${morningFocus}/bin/morning-focus"];
      RunAtLoad = true;
      StartInterval = 60;
      ProcessType = "Interactive";
      StandardOutPath = "/Users/matth/Library/Logs/morning-focus.log";
      StandardErrorPath = "/Users/matth/Library/Logs/morning-focus.log";
    };
  };
}
