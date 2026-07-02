{
  config,
  lib,
  pkgs,
  ...
}: let
  # Wraps a binary so it lands in the named systemd user slice. systemd-run
  # --scope places the process in a transient scope inside the slice; the
  # slice's MemoryHigh/Max/SwapMax then apply collectively to all instances.
  inSlice = slice: cmd: "systemd-run --user --slice=${slice} --scope -- ${cmd}";
in {
  # NOTE: every slice below sets MemoryKSM = "yes". hardware.ksm.enable alone
  # does NOTHING here — KSM only merges pages a process marks MADV_MERGEABLE,
  # and Chromium/Electron/Gecko never do (measured 2026-07-01: pages_sharing=0).
  # systemd 258's MemoryKSM=yes calls PR_SET_MEMORY_MERGE on every process in
  # the slice, forcing KSM onto the redundant browser engines (Zen/Beeper/Slack/
  # webapp-host all ship near-identical V8+Blink pages) without app cooperation.
  # Costs some kernel scan CPU; saves ~200-500 MB of duplicated runtime pages.
  # ── Slices ────────────────────────────────────────────────────────────────
  # Caps are based on observed peaks from memwatch logs (May 4–6 2026):
  #   Zen     12.4 GB peak  → cap 6/10, swap 6  (tightened: a 12 GB browser on
  #           a 16 GB laptop is the root memory hog. MemoryHigh=6G makes the
  #           kernel reclaim Zen's cold pages into zram well before the 10G
  #           hard MemoryMax, keeping resident set down without OOM-killing it;
  #           swap raised to 6G so reclaimed pages have somewhere to land.)
  #   Brave    5.3 GB peak  → cap 4/6,  swap 2
  #   Cursor   1.4 GB peak (but Code/Cursor combined hit 5.2 GB) → cap 4/6, swap 2
  #   Beeper   1.5 GB peak  → cap 2/3,  swap 1   (raised from earlier 1G/1.5G suggestion)
  systemd.user.slices = {
    "app-zen" = {
      Unit.Description = "Memory-capped slice for Zen Browser";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "6G";
        MemoryMax = "10G";
        MemorySwapMax = "6G";
      };
    };
    "app-brave" = {
      Unit.Description = "Memory-capped slice for Brave";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "4G";
        MemoryMax = "6G";
        MemorySwapMax = "2G";
      };
    };
    "app-beeper" = {
      Unit.Description = "Memory-capped slice for Beeper";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "2G";
        MemoryMax = "3G";
        MemorySwapMax = "1G";
      };
    };
    # Slack was measured at ~1 GB resident and uncapped (2026-06-30), the second
    # of only two >1 GB apps escaping this cap system. Same envelope as Beeper —
    # both are single-workspace Electron chat clients. Note: Beeper already
    # aggregates Slack, so the lower-RAM path is to run only one of the two.
    "app-slack" = {
      Unit.Description = "Memory-capped slice for Slack";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "2G";
        MemoryMax = "3G";
        MemorySwapMax = "1G";
      };
    };
    # The Chromium --app webapp host (Linear/Calendar/Gemini/Claude.ai, all
    # sharing ~/.config/chromium-app so they run as ONE instance) was ~1.4 GB
    # and uncapped. All launcher scripts route through this slice so whichever
    # window opens first places the shared process here.
    "app-webapps" = {
      Unit.Description = "Memory-capped slice for the Chromium webapp host";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "2G";
        MemoryMax = "3G";
        MemorySwapMax = "2G";
      };
    };
    "app-cursor" = {
      Unit.Description = "Memory-capped slice for Cursor";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "4G";
        MemoryMax = "6G";
        MemorySwapMax = "2G";
      };
    };
  };

  # ── Desktop entry overrides ───────────────────────────────────────────────
  # Filenames intentionally match the system-installed .desktop files so the
  # XDG search order picks up our ~/.local/share/applications/ versions first.
  # Existing process instances are NOT moved into the new slice — restart the
  # app (or reboot) for caps to take effect.
  xdg.desktopEntries = {
    "zen-beta" = {
      name = "Zen Browser (Beta)";
      genericName = "Web Browser";
      exec = inSlice "app-zen.slice" "zen-beta --name zen-beta %U";
      icon = "zen-browser";
      type = "Application";
      startupNotify = true;
      categories = ["Network" "WebBrowser"];
      mimeType = [
        "text/html"
        "text/xml"
        "application/xhtml+xml"
        "application/vnd.mozilla.xul+xml"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
      ];
      settings.StartupWMClass = "zen-beta";
      actions = {
        "new-private-window" = {
          name = "New Private Window";
          exec = inSlice "app-zen.slice" "zen-beta --private-window %U";
        };
        "new-window" = {
          name = "New Window";
          exec = inSlice "app-zen.slice" "zen-beta --new-window %U";
        };
        "profile-manager-window" = {
          name = "Profile Manager";
          exec = inSlice "app-zen.slice" "zen-beta --ProfileManager";
        };
      };
    };

    "brave-browser" = {
      name = "Brave Web Browser";
      genericName = "Web Browser";
      exec = inSlice "app-brave.slice" "brave %U";
      icon = "brave-browser";
      type = "Application";
      startupNotify = true;
      categories = ["Network" "WebBrowser"];
      mimeType = [
        "text/html"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "application/xhtml+xml"
      ];
      settings.StartupWMClass = "Brave-browser";
    };

    "beepertexts" = {
      name = "Beeper";
      comment = "Beeper";
      # --js-flags caps V8 old-space at 512 MB — a chat client never needs the
      # multi-GB heap V8 will otherwise grow to. Applies to all Electron procs.
      exec = inSlice "app-beeper.slice" "beeper --no-sandbox --force-device-scale-factor=1.25 --js-flags=--max-old-space-size=512 %U";
      icon = "beepertexts";
      type = "Application";
      mimeType = ["x-scheme-handler/beeper"];
      settings.StartupWMClass = "Beeper";
    };

    "slack" = {
      name = "Slack";
      genericName = "Instant Messaging";
      exec = inSlice "app-slack.slice" "slack -s --js-flags=--max-old-space-size=512 %U";
      icon = "slack";
      type = "Application";
      startupNotify = true;
      categories = ["Network" "InstantMessaging" "GNOME" "GTK"];
      mimeType = ["x-scheme-handler/slack"];
      settings.StartupWMClass = "Slack";
    };

    "cursor" = {
      name = "Cursor";
      genericName = "Text Editor";
      comment = "Code Editing. Redefined.";
      exec = inSlice "app-cursor.slice" "cursor %F";
      icon = "cursor";
      type = "Application";
      startupNotify = true;
      categories = ["Utility" "TextEditor" "Development" "IDE"];
      settings.StartupWMClass = "cursor";
      actions = {
        "new-empty-window" = {
          name = "New Empty Window";
          icon = "cursor";
          exec = inSlice "app-cursor.slice" "cursor --new-window %F";
        };
      };
    };
  };
}
