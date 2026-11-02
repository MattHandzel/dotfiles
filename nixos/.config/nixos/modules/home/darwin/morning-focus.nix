# Morning focus: the first time the laptop is used each morning, quit the
# messaging apps, open today's daily note, and walk Matt through his
# arrive-at-work routine.
#
# WHY (2026-10-01, CFAR TAPs class): Matt's TAP trigger is "I open my laptop".
# The action he wanted was to kill every distraction and start on the daily
# note's top task, not on Slack. This makes the first half of that action
# automatic, so the only thing left to do is the task itself.
#
# ROUTINE (2026-11-02, Matt's weekly-review note): "open daily note. actually
# _read_ the goals and the cfar taps, write out my daily tasks, think through
# the challenge of my day." After opening the note, a dialog lists those steps
# (a dialog, not a banner, so Do Not Disturb doesn't hide it). The routine
# counts as done once "## Challenge of the Day" in the note has any text. Until
# then, and until 12:00, it nudges again: 15 min after "Snooze", 25 min after
# "Start", at most 3 dialogs a day. Done/missed lines go to the log.
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
      done_stamp="$state_dir/routine-done"
      nudges_file="$state_dir/nudges"   # "<date> <count>"
      next_file="$state_dir/next-nudge" # epoch seconds
      today="$(date +%F)"
      note="$HOME/Obsidian/Main/dailies/$today.md"
      max_nudges=3
      force=0
      [ "''${1:-}" = "--force" ] && force=1
      log() { echo "$(date -u +%FT%TZ) $*"; }

      # Any non-blank line under "## Challenge of the Day" = routine done.
      challenge_written() {
        [ -f "$note" ] || return 1
        awk '/^## Challenge of the Day/{f=1;next} /^## /{f=0} f && /[^[:space:]]/{n++} END{exit n?0:1}' "$note"
      }

      present() { # unlocked screen + input in the last 2 min
        # Locked screen: CGSSessionScreenIsLocked only appears while locked.
        # Both readers below consume all of ioreg's output: one that stops
        # early (grep -q, awk exit) SIGPIPEs ioreg, and pipefail turns that
        # into exit 141 (idle) or "not locked" (lock).
        if ioreg -n Root -d1 -a | grep CGSSessionScreenIsLocked >/dev/null; then return 1; fi
        idle="$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/ && !n++ {print int($NF/1000000000)}')"
        [ "''${idle:-9999}" -lt 120 ]
      }

      open_note() {
        if [ -f "$note" ]; then
          open "obsidian://open?vault=Main&file=dailies%2F$today"
        else
          open -a Obsidian
        fi
      }

      # Detached dialog; its button choice sets the next nudge time.
      # AbandonProcessGroup keeps launchd from killing it when this run exits.
      routine_dialog() {
        local n=$1 head msg
        if [ "$n" -eq 1 ]; then
          head="Good morning. Daily note is open. Before anything else:"
        else
          head="Nudge $n of $max_nudges: Challenge of the Day is still empty."
        fi
        msg="$head

      1. Read the goals, slowly.
      2. Read the CFAR TAPs, one by one. Actually read them.
      3. Write out today's tasks under Top Tasks.
      4. Think through the challenge of your day and write it under Challenge of the Day.

      Done when Challenge of the Day has something in it."
        (
          r="$(osascript -e 'on run argv' \
            -e 'set r to display dialog (item 2 of argv) with title (item 1 of argv) buttons {"Snooze 15 min", "Start"} default button "Start" giving up after 600' \
            -e 'if gave up of r then return "gaveup"' \
            -e 'return button returned of r' -e 'end run' \
            "Morning routine" "$msg" 2>/dev/null || echo error)"
          now="$(date +%s)"
          case "$r" in
            Snooze*) echo $((now + 900)) > "$next_file" ;;
            Start) echo $((now + 1500)) > "$next_file"; open_note ;;
            *) echo $((now + 900)) > "$next_file" ;;
          esac
          log "dialog $n: $r"
        ) </dev/null >>"$HOME/Library/Logs/morning-focus.log" 2>&1 &
      }

      nudge_count() {
        d=""; c=0
        if [ -f "$nudges_file" ]; then read -r d c < "$nudges_file" || true; fi
        if [ "''${d:-}" = "$today" ]; then echo "''${c:-0}"; else echo 0; fi
      }

      mkdir -p "$state_dir"
      hour="$(date +%H)"
      in_window=0
      [ "$hour" -ge 5 ] && [ "$hour" -lt 12 ] && in_window=1

      # Follow-up ticks: after the first run today, until noon.
      if [ "$force" -eq 0 ] && [ "$(cat "$stamp" 2>/dev/null || true)" = "$today" ]; then
        [ "$(cat "$done_stamp" 2>/dev/null || true)" = "$today" ] && exit 0
        if challenge_written; then
          echo "$today" > "$done_stamp"
          log "routine done (Challenge of the Day written)"
          exit 0
        fi
        if [ "$in_window" -eq 0 ]; then
          echo "$today" > "$done_stamp"
          log "routine not done by noon (Challenge of the Day empty)"
          exit 0
        fi
        n="$(nudge_count)"
        [ "$n" -lt "$max_nudges" ] || exit 0
        [ "$(date +%s)" -ge "$(cat "$next_file" 2>/dev/null || echo 0)" ] || exit 0
        present || exit 0
        n=$((n + 1))
        echo "$today $n" > "$nudges_file"
        echo $(( $(date +%s) + 1800 )) > "$next_file" # placeholder until a button is pressed
        open_note
        routine_dialog "$n"
        exit 0
      fi

      if [ "$force" -eq 0 ]; then
        [ "$in_window" -eq 1 ] || exit 0
        present || exit 0
      fi

      echo "$today" > "$stamp"

      closed=()
      for app in ${pkgs.lib.escapeShellArgs apps}; do
        if [ "$(osascript -e "application \"$app\" is running" 2>/dev/null)" = "true" ]; then
          osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || true
          closed+=("$app")
        fi
      done

      open_note
      log "closed: ''${closed[*]:-none}; opened daily note"

      if challenge_written; then
        echo "$today" > "$done_stamp"
        log "routine already done"
        exit 0
      fi
      echo "$today 1" > "$nudges_file"
      echo $(( $(date +%s) + 1800 )) > "$next_file"
      rm -f "$done_stamp"
      routine_dialog 1
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
      AbandonProcessGroup = true;
      StandardOutPath = "/Users/matth/Library/Logs/morning-focus.log";
      StandardErrorPath = "/Users/matth/Library/Logs/morning-focus.log";
    };
  };
}
