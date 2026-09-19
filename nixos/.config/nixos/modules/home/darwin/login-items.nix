# Apps that must already be running the moment Matt logs in.
#
# WHY LAUNCHD AGENTS AND NOT THE LOGIN ITEMS LIST: macOS's "Open at Login"
# (System Settings > General > Login Items & Extensions) is not declarative. It
# lives in a per-user Background Task Management database that nothing in this
# flake can write, so anything added there by hand survives `rebuild` without
# ever appearing in the config, and the config can never remove it again. A
# RunAtLoad agent is the flake-owned equivalent: launchd fires it once per
# login, `open -a` hands the app off to LaunchServices and exits immediately.
#
# KeepAlive is deliberately false. These are launch-once agents, not
# supervisors: if Matt quits Beeper at 2pm he wants it to stay quit until the
# next login, and KeepAlive = true would respawn it within seconds.
#
# AeroSpace is deliberately NOT here. `start-at-login = true` in aerospace.nix
# makes AeroSpace register its own login item, and a second launch path racing
# that one is how you end up with two window managers fighting over the same
# tree. Slack, Wispr Flow and Raycast are already in the macOS Login Items list
# from before this module existed; they are left alone rather than duplicated.
{...}: let
  # `open -a` is idempotent. If the app is somehow already up, this activates
  # the existing instance instead of starting a second one.
  launchAtLogin = appName: {
    enable = true;
    config = {
      ProgramArguments = ["/usr/bin/open" "-a" appName];
      RunAtLoad = true;
      KeepAlive = false;
      # Interactive keeps launchd from throttling these the way it does
      # background maintenance jobs; they are user-facing GUI apps.
      ProcessType = "Interactive";
    };
  };
in {
  launchd.agents = {
    # "Beeper Desktop" is the bundle's real name on disk
    # (/Applications/Beeper Desktop.app). Plain "Beeper" does not resolve.
    beeper = launchAtLogin "Beeper Desktop";

    # Hammerspoon owns alt-Y / alt-shift-Y (notification dismissal), the
    # Option+brightness jumps, and the Option+Arrow browser-history shim. All of
    # those are dead until it is running, and its own "Launch at login"
    # preference is a GUI checkbox this flake cannot set.
    hammerspoon = launchAtLogin "Hammerspoon";

    # Turns Bluetooth off on sleep and back on at wake. Without it the Totem's
    # BLE link ("Bluetooth LE HID Activity") wakes the Mac every minute after
    # the lid closes. It only works while it is running (2026-09-14 Oops).
    bluesnooze = launchAtLogin "Bluesnooze";
  };
}
