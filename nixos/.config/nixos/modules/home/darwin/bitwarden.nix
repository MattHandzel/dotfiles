# Bitwarden: type the master password once per boot, in the desktop app, and
# unlock the Dia extension with Touch ID through the desktop app afterwards.
#
# The extension's "Unlock with biometrics" talks to Bitwarden.app over Chromium
# native messaging. The desktop app's "Allow browser integration" writes the
# host manifest only for the browsers in its getDarwinNMHS() table (Chrome,
# Chromium, Edge, Vivaldi, Zen, Helium, Firefox in 2026.8.0); Dia is not one of
# them, so Dia had no NativeMessagingHosts dir and the extension could only
# ever unlock with the master password (Oops run 20260913-131308). Dia (Arc
# lineage) reads user-level hosts from <User Data>/NativeMessagingHosts.
#
# Chrome started with --user-data-dir (the chromium-app profile behind the
# Calendar/Superhuman/claude.ai windows) reads user-level hosts from
# <user-data-dir>/NativeMessagingHosts, which Bitwarden.app never writes either
# (Oops run 20260914-095413).
{...}: let
  manifest = builtins.toJSON {
    name = "com.8bit.bitwarden";
    description = "Bitwarden desktop <-> browser bridge";
    path = "/Applications/Bitwarden.app/Contents/MacOS/desktop_proxy";
    type = "stdio";
    # Same origins Bitwarden.app writes for Chrome: the Web Store build first.
    allowed_origins = [
      "chrome-extension://nngceckbapebfimnlniiiahkandclblb/"
      "chrome-extension://hccnnhgbibccigepcmlgppchkpfdophk/"
      "chrome-extension://jbkfoedolllekgbhcbcoahefnbanhhlh/"
      "chrome-extension://ccnckbpmaceehanjmeomladnmlffdjgn/"
    ];
  };
in {
  home.file."Library/Application Support/Dia/User Data/NativeMessagingHosts/com.8bit.bitwarden.json".text = manifest;
  home.file.".config/chromium-app/NativeMessagingHosts/com.8bit.bitwarden.json".text = manifest;

  # The desktop app must be running for the extension's biometric unlock, and
  # its lock screen at login is the one master-password prompt per boot.
  # Same launch-once pattern as login-items.nix (no KeepAlive).
  launchd.agents.bitwarden = {
    enable = true;
    config = {
      ProgramArguments = ["/usr/bin/open" "-a" "Bitwarden"];
      RunAtLoad = true;
      KeepAlive = false;
      ProcessType = "Interactive";
    };
  };
}
