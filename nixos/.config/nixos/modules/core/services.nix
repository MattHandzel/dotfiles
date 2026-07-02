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
      SuspendState = "mem";
      HandleLidSwitch = "suspend";
      IdleAction = "suspend";
      IdleActionSec = "15min";
    };
  };

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
  # visible in `espanso log`). Across a suspend/resume cycle those evdev handles go
  # stale — espanso keeps running and `espanso status` still says "running", but it
  # never sees another keypress until the WORKER is restarted (espanso issues #2423,
  # #1732, #2262). The laptop suspends several times a day, so espanso silently went
  # deaf and the only recovery was a manual `espanso restart`.
  #
  # The USER systemd manager has no sleep.target to hook (verified: `systemctl
  # --user list-unit-files sleep.target` is empty), so a user-level resume unit is
  # impossible. Instead this SYSTEM oneshot is pulled in by sleep.target and ordered
  # After the sleep services, so its ExecStart runs on RESUME — restarting matth's
  # espanso worker and rebinding fresh evdev handles. `|| true` keeps the unit from
  # failing noisily if there is no graphical session (e.g. resume at the greeter).
  systemd.services.espanso-restart-on-resume = {
    description = "Restart espanso on resume (rebind stale Wayland evdev handles)";
    after = [
      "systemd-suspend.service"
      "systemd-hibernate.service"
      "systemd-hybrid-sleep.service"
      "systemd-suspend-then-hibernate.service"
    ];
    wantedBy = ["sleep.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "espanso-restart-on-resume" ''
        ${pkgs.systemd}/bin/systemctl --user --machine=${username}@.host restart espanso.service || true
      '';
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
