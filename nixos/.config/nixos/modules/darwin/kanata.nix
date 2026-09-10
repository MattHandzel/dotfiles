# kanata on macOS: the SAME keymap as the laptop (modules/shared/kanata-config.nix),
# launched from a launchd daemon instead of a systemd service.
#
# WHY A DAEMON AND NOT AN AGENT: kanata has to open the HID device, which needs
# to happen before login and independently of any GUI session.
#
# PERMISSIONS (Matt, once, then reboot — Phase 6 step 1/2):
#   1. Karabiner-Elements cask installs Karabiner-DriverKit-VirtualHIDDevice.
#      Approve the system extension in System Settings → Privacy & Security.
#   2. Grant Input Monitoring to the kanata binary. macOS keys that grant on the
#      BINARY PATH, and a store path changes on every rebuild, so the daemon is
#      pointed at a STABLE symlink (/usr/local/bin/kanata) that activation
#      re-points at the current store path. Grant the permission once, to the
#      symlink, and it survives every later switch.
#   3. Reboot.
#
# On macOS lmet/rmet are Command and lalt/ralt are Option, so the Corne layout's
# ring-finger "Super" becomes Cmd — the right modifier to land on here. The
# (lalt ralt) -> F14 chord still fires; bind F14 inside Wispr Flow.
#
# Fallback if the DriverKit extension is refused: Karabiner complex
# modifications (see modules/home/darwin/karabiner.nix, which already owns the
# caps/esc swap and the input-source toggle).
{pkgs, ...}: let
  kanataConfig = import ../shared/kanata-config.nix;

  cfg = pkgs.writeText "homerow.kbd" ''
    (defcfg
      ${kanataConfig.defcfgOptions}
      macos-dev-names-include (
    ${builtins.concatStringsSep "\n" (map (d: "    \"${d}\"") kanataConfig.darwinDeviceNames)}
      ))

    ${kanataConfig.body}
  '';

  stableBin = "/usr/local/bin/kanata";
in {
  # Install the binary at a permission-stable path on every switch.
  #
  # It must be a REAL FILE, not a symlink (verified on macOS 26.5, 2026-09-10).
  # macOS attributes an Input Monitoring grant to the RESOLVED executable, so a
  # symlink pointing into /nix/store hands the grant to a store path that the
  # next rebuild replaces — and kanata sits at "Input Monitoring permission not
  # yet decided" forever. Copying costs 3 MB and keeps the grant attached to
  # /usr/local/bin/kanata.
  #
  # Caveat that follows from the same rule: when the copy CHANGES (a kanata
  # version bump), macOS sees a different executable at the same path and the
  # permission has to be granted again. The `cmp` guard means that only happens
  # on an actual upgrade, not on every switch.
  system.activationScripts.kanataBinary.text = ''
    mkdir -p /usr/local/bin
    if ! cmp -s ${pkgs.kanata}/bin/kanata ${stableBin}; then
      echo "kanata: installing new binary at ${stableBin} (Input Monitoring must be re-granted)" >&2
      rm -f ${stableBin}
      cp ${pkgs.kanata}/bin/kanata ${stableBin}
      chmod 755 ${stableBin}
    fi

    # One kanata daemon, not two. The migration created a hand-written
    # /Library/LaunchDaemons/com.matth.kanata.plist while this module was being
    # debugged; leaving both loaded makes them fight over the keyboard device.
    if [ -f /Library/LaunchDaemons/com.matth.kanata.plist ]; then
      launchctl bootout system/com.matth.kanata 2>/dev/null || true
      mkdir -p /var/lib/kanata-superseded
      mv -f /Library/LaunchDaemons/com.matth.kanata.plist /var/lib/kanata-superseded/
      echo "kanata: superseded the hand-written com.matth.kanata daemon" >&2
    fi
  '';

  launchd.daemons.kanata = {
    serviceConfig = {
      Label = "com.matthandzel.kanata";
      ProgramArguments = [stableBin "--cfg" "${cfg}" "--nodelay"];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/kanata.log";
      StandardErrorPath = "/var/log/kanata.log";
      ProcessType = "Interactive";
    };
  };
}
