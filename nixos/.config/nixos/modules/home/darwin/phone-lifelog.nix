# phone-lifelog: every 5 min, copy what the phone already knows about Matt's day onto the Mac, for
# lifelog: its newest location fix, Android's app/screen/lock events, and Tasker Sleep Guard's home
# Wi-Fi log. Plus the Mac's own network. Matt, 2026-10-06: "You should also consider trying to get my
# location" and "a script ... on my phone to lifelog there as well".
#
# Read-only toward the phone (adb over Tailscale, connected the way adb-keepalive does it), and it
# never turns Tailscale on. Writes ~/.local/state/lifelog/ only; precise location stays out of the
# vault. The script is referenced by its vault path, so edits take effect on the next tick without a
# rebuild. Code and file layout: ~/Obsidian/Main/scripts/lifelog/phone_pull.py. Doc:
# areas/second-brain/lifelog.md
{
  config,
  pkgs,
  ...
}: {
  launchd.agents.phone-lifelog = {
    enable = true;
    config = {
      ProgramArguments = ["${pkgs.python3}/bin/python3" "-I" "${config.home.homeDirectory}/Obsidian/Main/scripts/lifelog/phone_pull.py"];
      StartInterval = 300;
      RunAtLoad = true;
      # Not ProcessType "Background" (2026-10-20): under memory pressure macOS starved it like the lifelog
      # ingest agents (see lifelog-store.nix); a pass sat 20+ min.
      Nice = 10;
      # adb from the user profile: the same binary as adb-keepalive, because an adb of another version
      # restarts the shared adb server and drops the phone. tailscale is for adb-connect.sh's status check.
      EnvironmentVariables.PATH = "/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin:${pkgs.coreutils}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      StandardOutPath = "${config.home.homeDirectory}/.local/state/lifelog/phone-pull.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/lifelog/phone-pull.log";
    };
  };
}
