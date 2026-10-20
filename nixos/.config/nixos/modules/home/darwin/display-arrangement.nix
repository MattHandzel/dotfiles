# Keep the secondary display stacked ABOVE the built-in one.
#
# WHY THIS EXISTS: the display arrangement is WindowServer state
# (/Library/Preferences/com.apple.windowserver.displays.plist), not something
# this flake can declare. Matt asked for the DELL above the laptop twice
# (2026-09-14 and 2026-09-20 Oops); the plist still holds an older "above"
# entry that had since reverted to side-by-side, so setting it once by hand is
# not enough. This module owns the applier and re-runs it at login; the
# Hammerspoon screen watcher (~/.hammerspoon/display_arrangement.lua) re-runs
# it when a display is plugged back in.
#
# Stacking the secondary above the primary is what makes AeroSpace's
# alt-k / alt-j (focus --boundaries all-monitors-outer-frame up/down) the keys
# that cross between monitors, instead of alt-l / alt-h.
{config, ...}: {
  home.file.".local/bin/display-stack-secondary" = {
    executable = true;
    text = ''
      #!/usr/bin/env python3
      """Place the secondary display directly above the primary, centred.

      Idempotent: exits 0 without touching anything when there is only one
      display or the secondary already sits above the primary.
      """
      import ctypes
      import ctypes.util
      import sys

      cg = ctypes.CDLL(ctypes.util.find_library("CoreGraphics"))


      class CGRect(ctypes.Structure):
          _fields_ = [
              ("x", ctypes.c_double),
              ("y", ctypes.c_double),
              ("w", ctypes.c_double),
              ("h", ctypes.c_double),
          ]


      cg.CGDisplayBounds.restype = CGRect
      cg.CGDisplayBounds.argtypes = [ctypes.c_uint32]
      cg.CGMainDisplayID.restype = ctypes.c_uint32

      KCG_CONFIGURE_PERMANENTLY = 2


      def active_displays():
          count = ctypes.c_uint32(0)
          ids = (ctypes.c_uint32 * 16)()
          cg.CGGetActiveDisplayList(16, ids, ctypes.byref(count))
          return [ids[i] for i in range(count.value)]


      def main():
          displays = active_displays()
          main_id = cg.CGMainDisplayID()
          others = [d for d in displays if d != main_id]
          if len(others) != 1:
              print(f"display-stack-secondary: {len(others)} secondary display(s), nothing to do")
              return 0

          secondary = others[0]
          primary_rect = cg.CGDisplayBounds(main_id)
          secondary_rect = cg.CGDisplayBounds(secondary)

          # Centre it horizontally on the primary and sit it directly on top.
          want_x = int(round(primary_rect.x + (primary_rect.w - secondary_rect.w) / 2))
          want_y = int(round(primary_rect.y - secondary_rect.h))

          if (int(round(secondary_rect.x)), int(round(secondary_rect.y))) == (want_x, want_y):
              print(f"display-stack-secondary: already at ({want_x},{want_y})")
              return 0

          config = ctypes.c_void_p()
          err = cg.CGBeginDisplayConfiguration(ctypes.byref(config))
          if err:
              print(f"CGBeginDisplayConfiguration -> {err}", file=sys.stderr)
              return 1
          err = cg.CGConfigureDisplayOrigin(
              config, ctypes.c_uint32(secondary), ctypes.c_int32(want_x), ctypes.c_int32(want_y)
          )
          if err:
              cg.CGCancelDisplayConfiguration(config)
              print(f"CGConfigureDisplayOrigin -> {err}", file=sys.stderr)
              return 1
          # Permanently: WindowServer writes it to its own plist, so it also
          # survives the next login rather than only this session.
          err = cg.CGCompleteDisplayConfiguration(
              config, ctypes.c_uint32(KCG_CONFIGURE_PERMANENTLY)
          )
          if err:
              print(f"CGCompleteDisplayConfiguration -> {err}", file=sys.stderr)
              return 1

          print(
              f"display-stack-secondary: moved display {secondary} "
              f"({secondary_rect.x:g},{secondary_rect.y:g}) -> ({want_x},{want_y})"
          )
          return 0


      if __name__ == "__main__":
          sys.exit(main())
    '';
  };

  # Login pass. A replug mid-session is handled by the Hammerspoon screen
  # watcher, which launchd has no equivalent trigger for.
  launchd.agents.display-stack-secondary = {
    enable = true;
    config = {
      ProgramArguments = ["${config.home.homeDirectory}/.local/bin/display-stack-secondary"];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Interactive";
      StandardOutPath = "${config.home.homeDirectory}/.local/state/display-stack-secondary.log";
      StandardErrorPath = "${config.home.homeDirectory}/.local/state/display-stack-secondary.log";
    };
  };
}
