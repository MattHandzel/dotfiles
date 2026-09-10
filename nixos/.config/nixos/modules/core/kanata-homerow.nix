# kanata for the laptop keyboard. DEFAULT layer is plain QWERTY — kanata runs
# only so that "both Alt keys together" can be detected as a real chord for
# speech-to-text (hyprland can't: it treats both Alts as the same ALT modifier,
# so a single Alt press wrongly fired the old `ALT, Alt_L` bind).
#
# Matt's custom Corne layout (+ home-row mods, nav/num layers, letter chords) is
# kept but DORMANT — reach it any time with Left-Alt + Esc, and Left-Alt + Esc
# again returns to QWERTY. Source of truth: github.com/MattHandzel/Corne.
#
# THE KEYMAP ITSELF LIVES IN modules/shared/kanata-config.nix, because the Mac
# runs the identical layers from a launchd daemon (modules/darwin/kanata.nix).
# Only the launcher and the device filter differ per platform.
#
# ── REVERSIBLE ───────────────────────────────────────────────────────────────
#   Nuclear off (no kanata at all, but then both-Alt STT stops too):
#     sudo systemctl stop kanata-homerow
#   Permanent: comment the import in hosts/laptop/default.nix, or roll back gen.
#
# Logs: journalctl -u kanata-homerow -f
{...}: let
  kanataConfig = import ../shared/kanata-config.nix;
in {
  services.kanata = {
    enable = true;
    keyboards.homerow = {
      devices = kanataConfig.linuxDevices;
      extraDefCfg = kanataConfig.defcfgOptions;
      config = kanataConfig.body;
    };
  };
}
