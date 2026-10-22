# sleep-check: each morning, did last night slip? (in bed/asleep after 21:30 or up after 06:45)
#
# WHY (2026-10-07, weekly review with Jeremy Kintana): Matt's 9pm-bed / 6am-wake routine holds until
# one late night breaks it, and then it doesn't come back. "If Claude notices that I have this problem,
# then Claude can send a message to you saying that I have this problem."
#
# HOW IT FIRES: a 5-minute tick. The script acts at most once a day: from 07:15, once the Mac is in use
# and the phone's morning data has reached the lifelog store, or at 11:00 regardless (until 15:00).
# A slip posts a notification plus a dialog (Do Not Disturb holds banners back) carrying a drafted
# message to Jeremy. Draft mode by default: it sends to Jeremy only when `send_to_jeremy = true` in
# scripts/sleep-check/config.toml. The script is referenced by its vault path, so edits and config
# changes apply on the next tick without a rebuild.
#
# Code: ~/Obsidian/Main/scripts/sleep-check. Doc: areas/second-brain/sleep-check.md
# Manual: `sleep-check run --force` (judge now), `run --test` (sample notification, never sends).
# Log: ~/Library/Logs/sleep-check.log (one line per judged morning).
#
# OFF since 2026-10-22: Matt stopped it ("no longer effective"). Flip enable back to true to restart.
{
  config,
  pkgs,
  ...
}: {
  launchd.agents.sleep-check = {
    enable = false;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${config.home.homeDirectory}/Obsidian/Main/scripts/sleep-check/sleep_check.py" "run"];
      StartInterval = 300;
      RunAtLoad = true;
      ProcessType = "Interactive";
      # The dialog is a detached osascript that outlives the run; don't let launchd reap it.
      AbandonProcessGroup = true;
      # uv (Beeper send, only when auto-send is on) lives in the nix profile.
      EnvironmentVariables.PATH = "${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/sleep-check.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/sleep-check.log";
    };
  };
}
