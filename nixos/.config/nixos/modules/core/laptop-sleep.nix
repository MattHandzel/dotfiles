{...}: {
  # ── Sleep on the Acer Swift SF16-51T ───────────────────────────────────────
  #
  # Two hardware facts drive this file. Both were measured on 2026-08-03; the
  # evidence stays here so it doesn't have to be re-derived.
  #
  # 1. The firmware exposes no S3. The kernel reports
  #    `ACPI: PM: (supports S0 S4 S5)` at boot, and /sys/power/mem_sleep reads
  #    `[s2idle]` with no `deep` entry. This is a Modern-Standby-only laptop:
  #    `systemctl suspend` can only ever reach s2idle, where the CPU stays
  #    powered and any wakeup-armed device resumes it. That is why
  #    bootloader.nix pins mem_sleep_default=s2idle for this host — `deep`
  #    would simply be rejected by the firmware.
  #
  # 2. The ACPI lid device is non-compliant, and the kernel says so outright:
  #    `ACPI: button: The lid device is not compliant to SW_LID.` It emits
  #    spurious close->open pulses lasting 1.5-23 ms. Across 14 days of journal
  #    the two populations are unmistakable: real closures run 27 s to 9.6 h,
  #    the glitches are milliseconds.
  #
  # Together these are why suspend appeared broken. The lid was armed as a
  # system wakeup source, so one spurious pulse resumed the machine instantly.
  # The failing suspend on 2026-08-03 lasted 2 seconds (10:42:27 -> 10:42:29)
  # and was followed in that same second by
  # "Lid closed. Lid opened. Lid closed. Lid opened."
  # The lid wakeup counter (/sys/class/wakeup/wakeup47 = PNP0C0D:00) recorded
  # exactly 2 events for the whole boot, timestamped to that suspend and to
  # nothing else. Two control tests with an RTC alarm as the safety net —
  # `rtcwake -m freeze -s 30` and `systemctl suspend` with a 90 s alarm — each
  # held for their full window, which is what rules out the sleep path itself.
  #
  # Disarming the lid costs only wake-on-lid-open. The power button
  # (PNP0C0C:00) and the internal keyboard (i2c-1025174B:00) remain armed, so
  # the machine still wakes on a key press or the power button.
  services.udev.extraRules = ''
    # The lid's spurious millisecond pulses must never resume s2idle. Matched
    # on `bind` as well as `add` because acpi_button calls device_init_wakeup()
    # at probe — i.e. after the `add` event has already been processed, which
    # is the same reason the dock-NIC rule in hosts/laptop/default.nix needed
    # `bind` to take effect.
    ACTION=="add|bind", SUBSYSTEM=="acpi", ATTR{hid}=="PNP0C0D", ATTR{power/wakeup}="disabled"
  '';

  # Hibernation prerequisites. /var/lib/swapfile is a 16 GiB btrfs swapfile on
  # subvol /@ (RAM is 16 GB, so the image fits). The offset comes from
  #   btrfs inspect-internal map-swapfile -r /var/lib/swapfile
  # btrfs-snapshots.nix only snapshots /home, so these extents stay stable.
  #
  # Setting these two is inert until something actually hibernates: on a normal
  # boot the kernel finds no image signature at the offset and continues. They
  # are what makes `systemctl hibernate` — and therefore a future
  # HandleLidSwitch=suspend-then-hibernate — safe to use at all. Without them
  # hibernating would power off and resume into a *fresh* boot, losing the
  # session.
  boot.resumeDevice = "/dev/disk/by-uuid/74730e39-2dc6-46dd-bf48-bef37fea93e4";
  boot.kernelParams = ["resume_offset=1160608"];
}
