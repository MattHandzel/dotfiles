# Home Manager runs here as a NixOS module, so `home-manager-matth.service`
# activates the generation baked into the *system* generation at every boot:
#
#   ExecStart=/nix/store/<hash>-hm-setup-env /nix/store/<hash>-home-manager-generation
#
# That path is only ever updated by `nixos-rebuild switch`. `hm-switch` builds
# and activates the same derivation, but nothing writes it into the system
# generation — so the next boot re-activates the older, system-baked generation
# and silently throws the hm-switch away.
#
# This is a trap rather than a bug: the reverted state looks exactly like a fix
# that "never worked". It cost a real debugging cycle on 2026-07-26, when the
# Vicinae server unit had been repaired via hm-switch (PATH + Hyprland instance
# signature), verified working, and then reverted by a reboot to the pre-fix
# wrapper — with no signal anywhere that a revert had happened.
#
# `hm-switch` now records the generation it activated; this unit compares that
# stamp against whatever the boot actually activated and says so out loud when
# they differ. It cannot make hm-switch durable — only `rebuild` can — but it
# makes a silent revert impossible.
#
# 2026-07-31: the guard fired on every `rebuild`, immediately, claiming the
# change had been reverted by the command that was making it durable. Cause:
# nothing scoped this to boot. It is WantedBy=graphical-session.target, and HM's
# reloadSystemd restarts those units on every activation — including the one
# inside `nixos-rebuild switch` — so it ran mid-rebuild (journal showed 4 runs
# in one afternoon, none at boot) and compared the stale stamp against the new
# generation. The stamp now also carries the boot_id it was written in, and the
# guard stays silent unless the current boot differs; only a reboot can revert
# an hm-switch. A guard that cries wolf on every rebuild is worse than none,
# because it teaches you to dismiss the one notification that matters.
{pkgs, ...}: let
  driftGuard = pkgs.writeShellScript "hm-drift-guard" ''
    set -u

    # 2026-08-05, third occurrence of "the guard cries wolf on every rebuild".
    # The two previous fixes both patched the COMPARISON (boot_id, then the
    # stamp parser). Both missed the real shape of the bug, which is WHEN this
    # runs, not what it compares:
    #
    #   `rebuild` clears the stamp only AFTER nixos-rebuild switch returns, but
    #   HM's reloadSystemd restarts graphical-session units DURING that switch.
    #   So every rebuild has a window where a stamp that survived a reboot is
    #   compared against a generation that is not final yet. The boot_id check
    #   cannot help: that stamp legitimately belongs to an earlier boot.
    #
    # Measured on 2026-08-05: system profile updated 10:53:04, guard ran
    # 10:53:07 and notified, `rm -f` removed the stamp 10:53:08.
    #
    # A revert can only happen AT BOOT, so this only ever needs to run once per
    # boot. /run/user/$UID is tmpfs and is emptied at boot, so this marker makes
    # every activation-triggered re-run a no-op and kills the whole class.
    ran="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/hm-drift-guard.ran"
    [ -e "$ran" ] && exit 0
    : > "$ran"

    stamp="''${XDG_STATE_HOME:-$HOME/.local/state}/hm-switch-pending"
    unit=/etc/systemd/system/home-manager-matth.service

    # No pending hm-switch => nothing can have been reverted.
    [ -r "$stamp" ] || exit 0

    # Line 1: the generation hm-switch activated. Line 2: the boot it ran in.
    pending="$(${pkgs.coreutils}/bin/head -n1 "$stamp")"
    # tail|head, not sed: sed lives in gnused, and ${pkgs.coreutils}/bin/sed is
    # a path that does not exist. That failure is SILENT under `set -u` (a dead
    # command substitution just yields ""), which emptied stamp_boot, skipped
    # the boot check below, and warned on every rebuild anyway.
    stamp_boot="$(${pkgs.coreutils}/bin/tail -n +2 "$stamp" | ${pkgs.coreutils}/bin/head -n1)"
    if [ -z "$pending" ]; then
      ${pkgs.coreutils}/bin/rm -f "$stamp"
      exit 0
    fi

    # This unit is WantedBy=graphical-session.target, and Home Manager's
    # reloadSystemd restarts those on EVERY activation — including the
    # activation that runs inside `nixos-rebuild switch`. So it fires far more
    # often than "at boot", and mid-rebuild it would compare the old stamp
    # against the new generation and cry "reverted" at the very command that
    # makes the change durable. Only a REBOOT can revert an hm-switch, so if
    # the stamp was written during the current boot, nothing can have been
    # thrown away yet — stay quiet.
    current_boot="$(${pkgs.coreutils}/bin/cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
    if [ -n "$stamp_boot" ] && [ "$stamp_boot" = "$current_boot" ]; then
      exit 0
    fi

    baked=""
    if [ -r "$unit" ]; then
      baked="$(${pkgs.gnugrep}/bin/grep -o \
        '/nix/store/[a-z0-9]*-home-manager-generation' "$unit" \
        | ${pkgs.coreutils}/bin/head -n1)"
    fi

    # A rebuild has since baked exactly what hm-switch activated: durable now.
    if [ "$pending" = "$baked" ]; then
      ${pkgs.coreutils}/bin/rm -f "$stamp"
      exit 0
    fi

    # The notification daemon is not necessarily up yet at graphical-session
    # start, and a dropped notification here defeats the whole unit.
    for ((attempt = 0; attempt < 60; attempt++)); do
      if ${pkgs.libnotify}/bin/notify-send -u critical \
        "Home-Manager change was reverted by this boot" \
        "Your last hm-switch is NOT in the system generation, so this boot activated the older one. Run 'rebuild' to make it durable."; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 2
    done

    echo "hm-drift-guard: pending=$pending baked=$baked (could not notify)" >&2
    exit 1
  '';
in {
  systemd.user.services.hm-drift-guard = {
    Unit = {
      Description = "Warn when a boot reverted an hm-switch-only change";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${driftGuard}";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
