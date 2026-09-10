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
  # Re-point the permission-stable symlink at the current store path on every
  # switch, so Input Monitoring is granted once and never again.
  system.activationScripts.kanataSymlink.text = ''
    mkdir -p /usr/local/bin
    ln -sfn ${pkgs.kanata}/bin/kanata ${stableBin}
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
