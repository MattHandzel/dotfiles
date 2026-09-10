{
  pkgs,
  lib,
  username,
  ...
}: {
  services = {
    gvfs.enable = true;
    gnome.gnome-keyring.enable = true;
    dbus.enable = true;
    fstrim.enable = true;
    printing.enable = true;
    # netdata removed — btop+duf+procs cover monitoring needs
    espanso = {
      enable = true;
      package = pkgs.espanso-wayland;
    };
    avahi.enable = true;
    avahi.nssmdns4 = true;
    avahi.openFirewall = true;
  };

  services.printing.drivers = with pkgs; [gutenprint hplip brlaser];

  services.logind.settings = {
    Login = {
      HandlePowerKey = "suspend";
      HandleLidSwitch = "suspend";
      IdleAction = "suspend";
      IdleActionSec = "15min";
    };
  };

  # `SuspendState` is a [Sleep] key in sleep.conf, not a [Login] key in
  # logind.conf. It used to live in the block above, where systemd rejected it
  # outright — "/etc/systemd/logind.conf:7: Unknown key 'SuspendState' in
  # section [Login], ignoring." was in every boot's journal — so the setting
  # had never actually taken effect. Moved here so it does.
  systemd.sleep.extraConfig = ''
    SuspendState=mem
  '';

  virtualisation.docker.enable = true;

  # ROOT CAUSE of "espanso dead after boot": espanso's Wayland detect thread
  # connects to the compositor at startup and panics with `NoCompositor`
  # (espanso-detect/.../evdev/sync/wayland.rs) if Hyprland isn't accepting Wayland
  # connections yet — the worker exits 101 and the unit fails. The upstream module
  # binds espanso to graphical-session.target, which is reached ~2s BEFORE
  # Hyprland's Wayland socket is usable (verified from the boot log: target at
  # 11:09:38, compositor ready at 11:09:40), so espanso starts too early and
  # crashes; it only sometimes recovers via Restart=. On a slow boot it exhausts
  # the start-limit and stays dead until a manual restart.
  #
  # Fix: anchor to hyprland-session.target, which is reached ONLY once the
  # compositor is up (Hyprland itself stop/starts it from exec-once). mkForce
  # REPLACES the upstream WantedBy=graphical-session.target so espanso no longer
  # starts at the early target at all.
  systemd.user.services.espanso = {
    after = lib.mkForce ["hyprland-session.target"];
    wantedBy = lib.mkForce ["hyprland-session.target"];
    partOf = ["hyprland-session.target"];
    unitConfig = {
      # 0 = unlimited retries: a transient compositor race must never PERMANENTLY
      # fail the unit (the old 10-in-60s budget could still be exhausted on a slow
      # boot, leaving espanso dead until a manual restart).
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # ROOT CAUSE of "espanso goes flaky / stops expanding until I restart it": on
  # Wayland espanso reads keystrokes straight from /dev/input/event* (EVDEVSource,
  # visible in `espanso log`) and enumerates devices ONLY at worker startup — it
  # has NO hotplug support (espanso issues #2423, #1732, #2262). So the worker
  # goes silently deaf ("running" but never expanding) whenever its device set
  # becomes stale:
  #   - suspend/resume re-enumerates input devices (several times a day);
  #   - a keyboard appears AFTER the worker started (USB/Bluetooth hotplug —
  #     verified live: a Logitech keyboard interface present on the system was
  #     not held by the worker until a restart);
  #   - kanata (modules/core/kanata-homerow.nix) restarts: it exclusively grabs
  #     the real keyboard and re-emits through its own virtual device, so a new
  #     kanata device espanso hasn't grabbed = total deafness.
  #
  # Recovery = restart espanso AFTER the device set settles. Three layers:
  #   1. espanso-rebind (below): fires on resume (sleep.target) AND whenever
  #      udev sees a new keyboard-class device (hotplug, kanata restart).
  #   2. espanso-rebind-on-boot: boot-time race (further below).
  #   3. espanso-watchdog (below): 2-minutely health check that verifies the
  #      worker actually holds the devices Matt types through, restarting it if
  #      not — the catch-all for any failure mode not covered above.
  #
  # The USER systemd manager has no sleep.target to hook (verified: `systemctl
  # --user list-unit-files sleep.target` is empty), so these are SYSTEM units
  # reaching matth's user manager over the machined bus. `|| true` keeps them
  # from failing noisily if there is no graphical session (e.g. resume at the
  # greeter, or udev coldplug before login).
  #
  # NOTE: do NOT try to do this from an /etc/systemd/system-sleep hook — those
  # run while user.slice is still frozen, so `systemctl --user` always fails
  # with "Transport endpoint is not connected" (a prior attempt did exactly
  # that and never worked once).
  systemd.services.espanso-rebind = {
    description = "Rebind espanso evdev handles (resume / keyboard hotplug / kanata restart)";
    after = [
      "systemd-suspend.service"
      "systemd-hibernate.service"
      "systemd-hybrid-sleep.service"
      "systemd-suspend-then-hibernate.service"
    ];
    wantedBy = ["sleep.target"];
    # udev can trigger this in bursts (one event per re-enumerated device);
    # never let the default start-rate limit wedge the unit into "failed".
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "espanso-rebind" ''
        # Wait for device re-enumeration to finish, then give stragglers a
        # moment — restarting the instant of resume used to race the input
        # devices coming back, leaving the fresh worker deaf too.
        ${pkgs.systemd}/bin/udevadm settle --timeout=10 || true
        ${pkgs.coreutils}/bin/sleep 2
        ${pkgs.systemd}/bin/systemctl --user --machine=${username}@.host restart espanso.service || true
      '';
    };
  };

  # Any NEW keyboard-class device (external keyboard plugged in, kanata's
  # virtual device after a kanata restart, post-resume re-enumeration) →
  # rebind espanso, since it cannot hotplug. Espanso's own injection device is
  # excluded, or every rebind would trigger the next one in an infinite loop.
  # Wispr Flow's helper registers its own uinput keyboard, which otherwise looks
  # like a keyboard hotplug and re-triggers espanso-rebind. Espanso then tears
  # down and recreates ITS virtual device; any modifier held across that teardown
  # never gets its key-up, so wlroots latches Ctrl/Super permanently (the "stuck
  # modifier" bug). Excluded for the same reason espanso's own device already is.
  #
  # The TOTEM is excluded too (espanso-broken report #5): Matt never types
  # through the raw TOTEM node — kbd-relay (modules/home/kbd-relay.nix) grabs it
  # and forwards through the always-present "Keyboard Relay" device, which
  # espanso already holds. So a TOTEM (re)connect changes nothing espanso reads,
  # yet its BLE flapping used to restart espanso on every reconnect — each one a
  # multi-second deaf window. A keyboard that is grabbed-and-relayed must never
  # trigger a rebind; only devices espanso actually reads may.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="input", ENV{ID_INPUT_KEYBOARD}=="1", ATTRS{name}!="Espanso virtual device", ATTRS{name}!="Wispr Flow Linux Helper", ATTRS{name}!="*TOTEM*", TAG+="systemd", ENV{SYSTEMD_WANTS}+="espanso-rebind.service"
  '';

  # AT-SPI accessibility bus. Wispr Flow reads the focused app + text field over
  # AT-SPI; without this bus it logs "axContextTime: null" and falls back to
  # "Sending transcription request without having recieved context from helper",
  # which is why app detection and per-app tone (e.g. Thunderbird = email) fail.
  services.gnome.at-spi2-core.enable = true;
  environment.variables = {
    GNOME_ACCESSIBILITY = "1";
    QT_ACCESSIBILITY = "1";
  };

  # Catch-all watchdog: every 2 minutes verify the espanso worker holds a LIVE
  # fd to each device Matt actually types through — the kanata virtual device
  # (internal-keyboard path), the raw built-in keyboard, and the Keyboard Relay
  # (the TOTEM path; kbd-relay grabs the TOTEM and forwards through it). A fd
  # whose target was deleted does not count: that is the post-resume trap where
  # a device is recreated under the SAME event number, the path check passes,
  # and the worker is deaf anyway.
  #
  # Stale fds to devices that no longer EXIST (a dropped TOTEM node, an old
  # Wispr helper) are deliberately ignored (espanso-broken report #5): espanso
  # removes a vanished device from epoll and keeps expanding fine on the rest.
  # The old "any stale fd = deaf" rule turned every TOTEM disconnect into an
  # espanso restart every 10 minutes, around the clock — the restarts WERE the
  # breakage Matt kept reporting, not the cure. If unhealthy, restart espanso
  # (rate-limited to once per 10 min so a legitimately ungrabbable device can
  # never cause a restart loop). Root is required: espanso runs under a
  # capability wrapper, so /proc/<pid>/fd is unreadable from the user session.
  systemd.services.espanso-watchdog = {
    description = "Restart espanso if its worker no longer holds the active keyboards";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "espanso-watchdog" ''
        set -u
        PATH=${lib.makeBinPath [pkgs.coreutils pkgs.procps pkgs.gnugrep pkgs.gnused pkgs.systemd]}
        wpid="$(pgrep -o -f 'espanso worker' || true)"
        [ -n "$wpid" ] || exit 0 # worker down → espanso.service's own Restart= handles it

        fdlist="$(ls -l "/proc/$wpid/fd" 2>/dev/null)"
        [ -n "$fdlist" ] || exit 0 # worker mid-restart/gone — judge it next tick

        missing=""
        for namefile in /sys/class/input/event*/device/name; do
          [ -e "$namefile" ] || continue
          name="$(cat "$namefile")"
          case "$name" in
            kanata | "AT Translated Set 2 keyboard" | "Keyboard Relay") ;;
            *) continue ;;
          esac
          ev="''${namefile%/device/name}"
          ev="''${ev##*/}"
          # A live fd's symlink ends with the path; a stale one ends "(deleted)".
          printf '%s\n' "$fdlist" | grep -Eq "> /dev/input/$ev\$" || missing="$missing $name($ev)"
        done

        [ -z "$missing" ] && exit 0

        now="$(date +%s)"
        last="$(cat /run/espanso-watchdog.last 2>/dev/null || echo 0)"
        if [ "$((now - last))" -lt 600 ]; then
          echo "worker $wpid unhealthy (missing:$missing) — within rate limit, not restarting"
          exit 0
        fi
        echo "$now" >/run/espanso-watchdog.last
        echo "worker $wpid deaf (missing:$missing) — restarting espanso"
        systemctl --user --machine=${username}@.host restart espanso.service || true
      '';
    };
  };
  systemd.timers.espanso-watchdog = {
    description = "Periodic espanso deafness check";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "2min";
    };
  };

  # ROOT CAUSE of "espanso does not work upon reboot": the boot logs show espanso
  # starting cleanly every boot (no NoCompositor panic, no restart) — yet it does
  # not expand until a manual `espanso restart`. This is the SAME stale-evdev bug
  # as the resume case above, but at cold boot: on Wayland the worker grabs
  # /dev/input/event* (EVDEVSource) the instant hyprland-session.target is reached,
  # which is BEFORE udev/libinput have finished enumerating the keyboard(s). The
  # worker binds to an incomplete/early device set, `espanso status` reports
  # "running", but it never sees a keypress — boot-time deafness. The resume
  # watchdog only fires on sleep.target, so it never covered the boot path.
  #
  # Fix: a user oneshot pulled in by hyprland-session.target that, once espanso is
  # up AND input devices have settled, restarts the worker ONCE to rebind fresh
  # evdev handles. This is a user unit (no --machine needed) ordered After espanso
  # so it cannot race the daemon's own start. The restart is unconditional — it
  # also harmlessly re-grabs on the (rare) boot where the first grab was complete.
  systemd.user.services.espanso-rebind-on-boot = {
    description = "Rebind espanso evdev handles once after boot (grab races input enumeration)";
    after = ["espanso.service" "hyprland-session.target"];
    wants = ["espanso.service"];
    partOf = ["hyprland-session.target"];
    wantedBy = ["hyprland-session.target"];
    serviceConfig = {
      Type = "oneshot";
      # Give udev/libinput time to enumerate all keyboards before re-grabbing.
      ExecStart = pkgs.writeShellScript "espanso-rebind-on-boot" ''
        sleep 5
        ${pkgs.systemd}/bin/systemctl --user restart espanso.service || true
      '';
    };
  };
}
