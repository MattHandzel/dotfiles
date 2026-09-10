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
  # DESIGN (revised 2026-07-04): these slices set ONLY MemoryHigh — a *soft*
  # throttle — never a hard MemoryMax. MemoryHigh makes the kernel aggressively
  # reclaim a slice's cold pages into zram once the app grows past it, which is
  # exactly the anti-thrash intent here, but it CANNOT kill the app. A hard
  # MemoryMax (used previously) OOM-kills a process *inside that one cgroup* the
  # moment it can't reclaim below the ceiling — independent of system-wide free
  # RAM — which is why apps were dying with the laptop 60% free. Likewise the
  # old low MemorySwapMax caps starved reclaim of anywhere to land, forcing the
  # hard cap to be hit sooner. Both are gone. Genuine system-wide exhaustion is
  # handled by systemd-oomd + zram (see hosts/laptop/default.nix), which look at
  # real pressure across the whole session rather than per-app ceilings.
  # MemoryHigh values track observed peaks from memwatch logs (May 4–6 2026):
  #   Zen 12.4 GB · Brave 5.3 GB · Cursor 1.4 GB (Code+Cursor 5.2 GB) · Beeper 1.5 GB
  systemd.user.slices = {
    "app-zen" = {
      Unit.Description = "Memory-throttled slice for Zen Browser";
      Slice = {
        MemoryKSM = "yes";
        # Raised 6G→8G (2026-07-09): at 6G the slice showed 45M pgscan_direct +
        # 59M workingset_refault_anon — Zen's allocating threads were being
        # direct-reclaim throttled at the ceiling (memory.high sleeps every
        # allocation batch), which surfaced as multi-second stalls on typing
        # and tab switches. 8G still forces cold pages to zram well before the
        # 12.4G observed peak, without throttling the foreground working set.
        MemoryHigh = "8G";
        # Favor the interactive browser over sibling app slices when background
        # jobs saturate the CPU.
        CPUWeight = 200;
      };
    };
    # Lifelog's periodic archival jobs (tar|zstd -T0 -10, ffmpeg thumbnailing)
    # ran unconstrained in the session scope and stalled the whole desktop
    # (measured 2026-07-09 during a run: system IO PSI full avg10 ≈ 27%,
    # memory PSI full ≈ 15%, load 5.2). Low weights confine them to idle
    # capacity; the small MemoryHigh keeps their page-cache churn from
    # evicting interactive apps' working sets. Launched into this slice by
    # the Hyprland exec-once entry (hyprland/config.nix).
    "app-lifelog" = {
      Unit.Description = "Background-priority slice for the lifelog logger";
      Slice = {
        CPUWeight = 20;
        IOWeight = 20;
        MemoryHigh = "1G";
      };
    };
    "app-brave" = {
      Unit.Description = "Memory-throttled slice for Brave";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "4G";
      };
    };
    "app-beeper" = {
      Unit.Description = "Memory-throttled slice for Beeper";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "2G";
      };
    };
    # Slack was measured at ~1 GB resident and uncapped (2026-06-30), the second
    # of only two >1 GB apps escaping this cap system. Same envelope as Beeper —
    # both are single-workspace Electron chat clients. Note: Beeper already
    # aggregates Slack, so the lower-RAM path is to run only one of the two.
    "app-slack" = {
      Unit.Description = "Memory-throttled slice for Slack";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "2G";
      };
    };
    # The Chromium --app webapp host (Linear/Calendar/Gemini/Claude.ai, all
    # sharing ~/.config/chromium-app so they run as ONE instance) was ~1.4 GB
    # and uncapped. All launcher scripts route through this slice so whichever
    # window opens first places the shared process here.
    "app-webapps" = {
      Unit.Description = "Memory-throttled slice for the Chromium webapp host";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "2G";
      };
    };
    "app-cursor" = {
      Unit.Description = "Memory-throttled slice for Cursor";
      Slice = {
        MemoryKSM = "yes";
        MemoryHigh = "4G";
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
